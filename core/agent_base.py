"""AgentForge Core — Shared ReAct loop, tool registry, cost tracking, structured logging."""
import boto3, json, logging, time, os
from typing import Any, Callable
from dataclasses import dataclass, field

logger = logging.getLogger("agentforge")
logger.setLevel(logging.INFO)

bedrock = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION", "us-east-1"))
MAX_ITERATIONS = 10
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-sonnet-20240229-v1:0")


@dataclass
class ToolResult:
    success: bool
    data: dict = field(default_factory=dict)
    error: str = ""
    retry_safe: bool = False


class ToolRegistry:
    def __init__(self):
        self._tools: dict[str, Callable] = {}
        self._schemas: dict[str, dict] = {}

    def register(self, name: str, func: Callable, schema: dict):
        self._tools[name] = func
        self._schemas[name] = schema

    def execute(self, name: str, params: dict) -> ToolResult:
        if name not in self._tools:
            return ToolResult(success=False, error=f"Unknown tool: {name}")
        try:
            result = self._tools[name](**params)
            return ToolResult(success=True, data=result)
        except Exception as e:
            logger.error(f"Tool {name} failed: {e}")
            return ToolResult(success=False, error=str(e), retry_safe=True)

    def get_tool_descriptions(self) -> str:
        descs = []
        for name, schema in self._schemas.items():
            descs.append(f"Tool: {name}\nDescription: {schema.get('description','')}\nParams: {json.dumps(schema.get('parameters',{}))}")
        return "\n\n".join(descs)


class CostTracker:
    PRICING = {
        "anthropic.claude-3-sonnet-20240229-v1:0": {"input": 0.000003, "output": 0.000015},
        "anthropic.claude-3-haiku-20240307-v1:0": {"input": 0.00000025, "output": 0.00000125},
    }

    def __init__(self):
        self.total_input_tokens = 0
        self.total_output_tokens = 0
        self.total_cost_usd = 0.0
        self.invocations = 0

    def record(self, model_id: str, input_tokens: int, output_tokens: int):
        self.total_input_tokens += input_tokens
        self.total_output_tokens += output_tokens
        self.invocations += 1
        p = self.PRICING.get(model_id, {"input": 0.000003, "output": 0.000015})
        cost = (input_tokens * p["input"]) + (output_tokens * p["output"])
        self.total_cost_usd += cost
        return cost

    def summary(self) -> dict:
        return {"total_input_tokens": self.total_input_tokens, "total_output_tokens": self.total_output_tokens, "total_cost_usd": round(self.total_cost_usd, 6), "invocations": self.invocations}


class AgentBase:
    def __init__(self, name: str, instruction: str):
        self.name = name
        self.instruction = instruction
        self.tools = ToolRegistry()
        self.cost_tracker = CostTracker()
        self.turns = []

    def invoke_llm(self, messages: list[dict]) -> dict:
        start = time.time()
        resp = bedrock.invoke_model(modelId=MODEL_ID, body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31", "max_tokens": 4096,
            "system": self.instruction, "messages": messages}))
        body = json.loads(resp["body"].read())
        usage = body.get("usage", {})
        cost = self.cost_tracker.record(MODEL_ID, usage.get("input_tokens", 0), usage.get("output_tokens", 0))
        logger.info(json.dumps({"event": "llm_call", "agent": self.name, "latency_ms": int((time.time()-start)*1000), "cost_usd": round(cost,6)}))
        return body

    def run(self, user_input: str) -> str:
        messages = [{"role": "user", "content": user_input}]
        for i in range(MAX_ITERATIONS):
            response = self.invoke_llm(messages)
            content = response["content"][0]["text"]
            if "TOOL_CALL:" not in content:
                logger.info(json.dumps({"event": "agent_done", "agent": self.name, "iterations": i+1, **self.cost_tracker.summary()}))
                return content
            tool_name, tool_input = self._parse_tool_call(content)
            result = self.tools.execute(tool_name, tool_input)
            self.turns.append({"tool": tool_name, "result": result})
            messages.append({"role": "assistant", "content": content})
            messages.append({"role": "user", "content": f"Tool result: {json.dumps(result.data if result.success else {'error': result.error})}"})
        return "Max iterations reached."

    def _parse_tool_call(self, content: str) -> tuple:
        try:
            m = content.index("TOOL_CALL:")
            call = content[m+10:].strip()
            p = call.index("(")
            name = call[:p].strip()
            params = json.loads(call[p+1:call.rindex(")")])
            return name, params
        except (ValueError, json.JSONDecodeError):
            return "unknown", {}

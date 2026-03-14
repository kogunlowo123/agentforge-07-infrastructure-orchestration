import json, pytest
from core.agent_base import ToolRegistry, ToolResult, CostTracker

class TestToolRegistry:
    def test_register_execute(self):
        r = ToolRegistry()
        r.register("echo", lambda msg: {"echo": msg}, {"description": "Echo"})
        res = r.execute("echo", {"msg": "hi"})
        assert res.success and res.data == {"echo": "hi"}

    def test_unknown_tool(self):
        r = ToolRegistry()
        res = r.execute("nope", {})
        assert not res.success

class TestCostTracker:
    def test_record(self):
        t = CostTracker()
        t.record("anthropic.claude-3-sonnet-20240229-v1:0", 1000, 500)
        assert t.invocations == 1 and t.total_cost_usd > 0

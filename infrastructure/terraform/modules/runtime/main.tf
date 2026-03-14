variable "project_name" { type = string }
variable "environment" { type = string }
variable "lambda_memory" { type = number; default = 512 }
variable "lambda_timeout" { type = number; default = 60 }
variable "bedrock_model_id" { type = string; default = "anthropic.claude-3-sonnet-20240229-v1:0" }

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "agent" {
  name = "${var.project_name}-${var.environment}-agent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "agent" {
  name = "${var.project_name}-${var.environment}-agent-policy"
  role = aws_iam_role.agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"], Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_model_id}" },
      { Effect = "Allow", Action = ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:Query","dynamodb:UpdateItem","dynamodb:DeleteItem"], Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project_name}-*" },
      { Effect = "Allow", Action = ["s3:GetObject","s3:PutObject","s3:ListBucket"], Resource = ["arn:aws:s3:::${var.project_name}-${var.environment}-*","arn:aws:s3:::${var.project_name}-${var.environment}-*/*"] },
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" }
    ]
  })
}

resource "aws_lambda_function" "agent" {
  function_name = "${var.project_name}-${var.environment}-agent"
  role          = aws_iam_role.agent.arn
  handler       = "agent.lambda_handler"
  runtime       = "python3.11"
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout
  filename      = "${path.module}/lambda.zip"
  environment { variables = { ENVIRONMENT = var.environment, BEDROCK_MODEL_ID = var.bedrock_model_id, SESSIONS_TABLE = "${var.project_name}-${var.environment}-sessions" } }
  tracing_config { mode = "Active" }
}

resource "aws_apigatewayv2_api" "agent" { name = "${var.project_name}-${var.environment}-api"; protocol_type = "HTTP" }
resource "aws_apigatewayv2_integration" "agent" { api_id = aws_apigatewayv2_api.agent.id; integration_type = "AWS_PROXY"; integration_uri = aws_lambda_function.agent.invoke_arn; payload_format_version = "2.0" }
resource "aws_apigatewayv2_route" "agent" { api_id = aws_apigatewayv2_api.agent.id; route_key = "POST /invoke"; target = "integrations/${aws_apigatewayv2_integration.agent.id}" }
resource "aws_apigatewayv2_stage" "agent" { api_id = aws_apigatewayv2_api.agent.id; name = var.environment; auto_deploy = true }
resource "aws_lambda_permission" "apigw" { action = "lambda:InvokeFunction"; function_name = aws_lambda_function.agent.function_name; principal = "apigateway.amazonaws.com"; source_arn = "${aws_apigatewayv2_api.agent.execution_arn}/*/*" }

output "lambda_arn" { value = aws_lambda_function.agent.arn }
output "api_endpoint" { value = "${aws_apigatewayv2_stage.agent.invoke_url}/invoke" }
output "role_arn" { value = aws_iam_role.agent.arn }

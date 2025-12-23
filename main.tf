############################################
# Provider
############################################
provider "aws" {
  region = "eu-west-1"
}

############################################
# 1. IAM Role for Bedrock Agent
############################################
resource "aws_iam_role" "bedrock_agent_role" {
  name = "bedrock-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock.amazonaws.com" }
    }]
  })
}

# Attach AWS-managed Bedrock Full Access policy
resource "aws_iam_role_policy_attachment" "bedrock_full_access" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}



############################################
# 2. Bedrock Agent
############################################


resource "aws_bedrockagent_agent" "main" {
  agent_name                  = "my-react-app-agent"
  foundation_model            = "arn:aws:bedrock:eu-west-1:644094189739:inference-profile/eu.amazon.nova-lite-v1:0"
  instruction                 = "You are a helpful assistant. Provide concise answers."
  agent_resource_role_arn     = aws_iam_role.bedrock_agent_role.arn
  idle_session_ttl_in_seconds = 600
}



############################################
# 3. IAM Role for Lambda
############################################
resource "aws_iam_role" "lambda_role" {
  name = "lambda-bedrock-invoker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Allow Lambda to invoke the Bedrock Agent
resource "aws_iam_role_policy" "lambda_bedrock_policy" {
  name = "lambda-bedrock-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "bedrock:InvokeAgent"
      Resource = "*"
    }]
  })
}

############################################
# 4. Lambda Packaging
############################################
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas"
  output_path = "${path.module}/lambda_function_payload.zip"
}

############################################
# 5. Lambda Function
############################################
resource "aws_lambda_function" "api_handler" {
  function_name    = "bedrock-api-handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  role   = aws_iam_role.lambda_role.arn
  handler = "index.lambda_handler"
  runtime = "python3.12"

  environment {
    variables = {
      AGENT_ID       = aws_bedrockagent_agent.main.agent_id
      AGENT_ALIAS_ID = "TSTALIASID" # Draft alias
    }
  }
}

############################################
# 6. CloudWatch Logs (Lambda)
############################################
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.api_handler.function_name}"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "lambda_logging_policy" {
  name = "lambda-logging-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.lambda_log_group.arn}:*"
    }]
  })
}

############################################
# 7. API Gateway (HTTP API)
############################################
resource "aws_apigatewayv2_api" "http_api" {
  name          = "bedrock-gateway"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /ask"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

############################################
# 8. API Gateway Logs + Stage
############################################
resource "aws_cloudwatch_log_group" "api_gw_log_group" {
  name              = "/aws/api-gateway/${aws_apigatewayv2_api.http_api.name}"
  retention_in_days = 7
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_log_group.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }
}

############################################
# 9. Allow API Gateway to Invoke Lambda
############################################
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

############################################
# Output
############################################
output "api_endpoint" {
  value = "${aws_apigatewayv2_api.http_api.api_endpoint}/ask"
}

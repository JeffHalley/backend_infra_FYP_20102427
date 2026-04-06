############################################
# Lambda Function - Main API Handler
############################################
resource "aws_lambda_function" "api_handler" {
  function_name    = "bedrock-sql-api-handler"
  filename         = data.archive_file.api_handler_zip.output_path
  source_code_hash = data.archive_file.api_handler_zip.output_base64sha256

  role        = aws_iam_role.lambda_role.arn
  handler     = "index.lambda_handler"
  runtime     = "python3.12"
  timeout     = 60
  memory_size = 512

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      MODEL_ID    = "eu.amazon.nova-lite-v1:0"
    }
  }
}

############################################
# Lambda Function - DB Connection
############################################
resource "aws_lambda_function" "db_conn" {
  function_name    = "bedrock-sql-db-conn"
  filename         = data.archive_file.db_conn_zip.output_path
  source_code_hash = data.archive_file.db_conn_zip.output_base64sha256

  role        = aws_iam_role.lambda_role.arn
  handler     = "db_conn.lambda_handler"
  runtime     = "python3.12"
  timeout     = 30
  memory_size = 512

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST = aws_instance.postgres.private_ip
      DB_NAME = "postgres"
      DB_USER = "lambda_reader"
      DB_PASS = "BedrockReadOnly2026!"
    }
  }

  layers = ["arn:aws:lambda:eu-west-1:770693421928:layer:Klayers-p312-psycopg2-binary:1"]
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# Give Bedrock permission to call your DB Lambda
resource "aws_lambda_permission" "allow_bedrock" {
  statement_id  = "AllowBedrockInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_conn.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.sql_agent.agent_arn
}

############################################
# Lambda Packaging
############################################

data "archive_file" "api_handler_zip" {
  type        = "zip"
  output_path = "${path.module}/api_handler_lambda.zip"

  # Main logic file
  source {
    content  = file("${path.module}/lambdas/index.py")
    filename = "index.py"
  }

  source {
    content  = file("${path.module}/lambdas/common_config.py")
    filename = "common_config.py"
  }

  source {
    content  = file("${path.module}/lambdas/tenant_logic.py")
    filename = "tenant_logic.py"
  }
}

data "archive_file" "db_conn_zip" {
  type        = "zip"
  output_path = "${path.module}/db_conn_lambda.zip"

  source {
    content  = file("${path.module}/db_lambda/db_conn.py")
    filename = "db_conn.py"
  }

  source {
    content  = file("${path.module}/db_lambda/utils.py")
    filename = "utils.py"
  }

}

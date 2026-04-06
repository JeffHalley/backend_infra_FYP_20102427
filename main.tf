
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

############################################
# IAM Role for Lambda
############################################
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-bedrock-invoker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = ["lambda.amazonaws.com", "bedrock.amazonaws.com"] }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_combined_policy" {
  name = "lambda-combined-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Converse",
          "bedrock:InvokeAgent",
          "bedrock:GetInferenceProfile",
          "bedrock:ListInferenceProfiles"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.db_conn.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.conversations.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

############################################
# IAM Role for Bedrock Agent
############################################
data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "bedrock_agent_policy" {
  name = "bedrock-agent-policy"
  role = aws_iam_role.bedrock_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeFoundationModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
          "arn:aws:bedrock:eu-west-1:*:inference-profile/eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
        ]
      },
      # ADD THESE:
      {
        Sid    = "MarketplaceSubscription"
        Effect = "Allow"
        Action = [
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe",
          "aws-marketplace:Unsubscribe"
        ]
        Resource = "*"
      },
      {
        Sid    = "BedrockAgentCore"
        Effect = "Allow"
        Action = [
          "bedrock:GetAgent",
          "bedrock:GetFoundationModel",
          "bedrock:GetInferenceProfile",
          "bedrock:ListInferenceProfiles"
        ]
        Resource = "*"
      },
      {
        Sid      = "LambdaInvoke"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.db_conn.arn
      }
    ]
  })
}

resource "aws_iam_role" "bedrock_agent_role" {
  name = "bedrock-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

############################################
# VPC Endpoints
############################################

resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-1.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [aws_security_group.lambda_sg.id]

  tags = { Name = "bedrock-runtime-endpoint" }
}

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.eu-west-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [data.aws_vpc.default.main_route_table_id]

  tags = { Name = "s3-gateway-endpoint" }
}
resource "aws_vpc_endpoint" "bedrock_agent_runtime" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-1.bedrock-agent-runtime"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [aws_security_group.lambda_sg.id]

  tags = { Name = "bedrock-agent-runtime-endpoint" }

}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.eu-west-1.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [data.aws_vpc.default.main_route_table_id]

  tags = { Name = "dynamodb-gateway-endpoint" }
}

resource "aws_vpc_endpoint" "lambda" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.eu-west-1.lambda"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [aws_security_group.lambda_sg.id]

  tags = { Name = "lambda-api-endpoint" }
}

############################################
# Lambda Security Group
############################################
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-to-postgres-sg"
  description = "Lambda outbound to Postgres"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################################
# Other Resources (API GW, EC2, Packaging)
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

resource "aws_apigatewayv2_api" "http_api" {
  name          = "bedrock-gateway"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS", "GET"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /ask"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "get_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /conversations"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "post_conversations_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /conversations"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

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

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

############################################
# data sources
############################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-arm64"]
  }
}

resource "aws_security_group" "postgres" {
  name        = "postgres-spot-sg"
  description = "Postgres access from Lambda"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "postgres" {
  ami           = data.aws_ami.al2023_arm.id
  instance_type = "t4g.small"
  subnet_id     = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [aws_security_group.postgres.id]

  key_name = "postgress_instance_keypair"

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y postgresql16-server
    /usr/bin/postgresql-setup --initdb
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /var/lib/pgsql/data/postgresql.conf
    echo "host all all 0.0.0.0/0 scram-sha-256" >> /var/lib/pgsql/data/pg_hba.conf
    systemctl enable postgresql
    systemctl start postgresql
  EOF

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"
    }
  }

  lifecycle {
    ignore_changes = [ami, user_data, instance_type]
  }

  tags = { Name = "postgres-spot" }
}


############################################
# Cognito User Pool
############################################
resource "aws_cognito_user_pool" "pool" {
  name = "chat-user-pool"

  # Allow users to sign up with email
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 8
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name            = "chat-app-client"
  user_pool_id    = aws_cognito_user_pool.pool.id
  generate_secret = false

  callback_urls = [
    "http://localhost:5173",
    "https://d3212o90xjuosc.cloudfront.net/"
  ]

  logout_urls = [
    "http://localhost:5173",
    "https://d3212o90xjuosc.cloudfront.net/"
  ]

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]
}



resource "aws_dynamodb_table" "conversations" {
  name         = "conversations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "sessionId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "sessionId"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = { Name = "conversations" }
}

############################################
# API Gateway Authorizer
############################################
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-auth"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.client.id]
    issuer   = "https://${aws_cognito_user_pool.pool.endpoint}"
  }
}

resource "aws_bedrockagent_agent" "sql_agent" {
  agent_name              = "sql-data-agent"
  foundation_model        = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn
  prepare_agent           = true
  description             = "SQL agent - Sonnet 4.5"


  //foundation_model = "eu.amazon.nova-pro-v1:0"
  // "eu.anthropic.claude-3-sonnet-20240229-v1:0"
  //eu.anthropic.claude-3-5-sonnet-20240620-v1:0

  # Use templatefile to inject your prompt.txt
  instruction = templatefile("${path.module}/prompt.txt", {
    table_name = "public.metrics"
  })

  idle_session_ttl_in_seconds = 3600

}

resource "aws_bedrockagent_agent_action_group" "db_action" {
  agent_id          = aws_bedrockagent_agent.sql_agent.agent_id
  agent_version     = "DRAFT"
  action_group_name = "postgress_query_group"

  action_group_executor {
    lambda = aws_lambda_function.db_conn.arn
  }
  api_schema {
    payload = file("${path.module}/DB_Action_Group.yaml")
  }
}

# Give Bedrock permission to call your DB Lambda
resource "aws_lambda_permission" "allow_bedrock" {
  statement_id  = "AllowBedrockInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_conn.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.sql_agent.agent_arn
}

output "api_endpoint" {
  value = "${aws_apigatewayv2_api.http_api.api_endpoint}/ask"
}

output "postgres_private_ip" {
  value = aws_instance.postgres.private_ip
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "cognito_region" {
  value = "eu-west-1"
}

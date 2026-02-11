############################################
# S3 Bucket for Knowledge Documents
############################################
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "kb_docs" {
  bucket        = "monitoring-kb-docs-${random_id.suffix.hex}"
  force_destroy = true # Allows terraform destroy even if files exist
}

############################################
# Local path to knowledge_base
############################################
locals {
  # Use the correct folder relative to this module
  kb_path = abspath("${path.module}/knowledge_base")
}

############################################
# Upload all Markdown files, preserving folder structure
############################################
resource "aws_s3_object" "kb_files" {
  for_each = fileset(local.kb_path, "**/*.md")  # Recursive glob
  bucket   = aws_s3_bucket.kb_docs.id
  key      = each.value                           # keeps subfolders like business/check_thresholds.md
  source   = "${local.kb_path}/${each.value}"
}




############################################
# Lambda Function
############################################
resource "aws_lambda_function" "api_handler" {
  function_name    = "bedrock-sql-api-handler"
  filename         = data.archive_file.api_handler_zip.output_path
  source_code_hash = data.archive_file.api_handler_zip.output_base64sha256

  role   = aws_iam_role.lambda_role.arn
  handler = "index.lambda_handler"
  runtime = "python3.12"
  timeout = 30
  memory_size = 512

  vpc_config {
  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [aws_security_group.lambda_sg.id]
}


  environment {
    variables = {
      MODEL_ID = "eu.amazon.nova-lite-v1:0"
      BUCKET_NAME = aws_s3_bucket.kb_docs.id
    }
  }
}


############################################
# IAM Role for Lambda (Updated)
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

resource "aws_iam_role_policy" "lambda_combined_policy" {
  name = "lambda-combined-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.kb_docs.arn,
          "${aws_s3_bucket.kb_docs.arn}/*"
        ]
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
# 4. Lambda Packaging
############################################

data "archive_file" "api_handler_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas"
  output_path = "${path.module}/api_handler_lambda.zip"
}

############################################
# 7. API Gateway (HTTP API) with CORS
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

# POST /ask route
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
# 9. Allow API Gateway to invoke Lambda
############################################
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

#Security Group: Postgres

resource "aws_security_group" "postgres" {
  name        = "postgres-spot-sg"
  description = "Postgres access from Lambda"
  vpc_id      = data.aws_vpc.default.id

  # TEMP SSH (remove after setup)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR.IP.ADDRESS/32"]
  }

  # Postgres
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

# lambda security Group

resource "aws_security_group" "lambda_sg" {
  name        = "lambda-to-postgres-sg"
  description = "Lambda outbound to Postgres"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ec2 spot instance

resource "aws_instance" "postgres" {
  ami           = data.aws_ami.al2023_arm.id
  instance_type = "t4g.small"
  subnet_id     = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [aws_security_group.postgres.id]

  key_name = "placeholder"

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
      spot_instance_type               = "persistent"
      instance_interruption_behavior   = "stop"
    }
  }

  tags = {
    Name = "postgres-spot"
  }
}




############################################
# Output
############################################
output "api_endpoint" {
  value = "${aws_apigatewayv2_api.http_api.api_endpoint}/ask"
}

output "postgres_private_ip" {
  value = aws_instance.postgres.private_ip
}

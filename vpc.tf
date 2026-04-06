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

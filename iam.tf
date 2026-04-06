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

############################################
# SES - Email Alerting
############################################

# Verify the sender email identity
resource "aws_ses_email_identity" "sender" {
  email = "jeffhalley420@gmail.com"
}

# Verify the recipient email identity
resource "aws_ses_email_identity" "recipient" {
  email = "jeffhalley420@gmail.com"
}

############################################
# Lambda - Alert Emailer
############################################

data "archive_file" "alert_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/alert_lambda.zip"

  source {
    content  = file("${path.module}/alert_lambda/metric_alert.py")
    filename = "lambda_alert.py"
  }
}

resource "aws_lambda_function" "alert_sender" {
  function_name    = "bedrock-metric-alert-sender"
  filename         = data.archive_file.alert_lambda_zip.output_path
  source_code_hash = data.archive_file.alert_lambda_zip.output_base64sha256

  role        = aws_iam_role.lambda_role.arn   # Reuses your existing lambda role
  handler     = "lambda_alert.lambda_handler"
  runtime     = "python3.12"
  timeout     = 30
  memory_size = 256


  environment {
    variables = {
      SENDER_EMAIL    = aws_ses_email_identity.sender.email
      RECIPIENT_EMAIL = aws_ses_email_identity.recipient.email
    }
  }

  depends_on = [aws_ses_email_identity.sender]
}

############################################
# SES Send Permission - added to existing lambda role policy
############################################

resource "aws_iam_role_policy" "lambda_ses_policy" {
  name = "lambda-ses-send-policy"
  role = aws_iam_role.lambda_role.id  # Attaches to your existing lambda role

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SESSendEmail"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = aws_ses_email_identity.sender.email
          }
        }
      }
    ]
  })
}

############################################
# Bedrock Agent - Alert Action Group
############################################

resource "aws_lambda_permission" "allow_bedrock_alert" {
  statement_id  = "AllowBedrockAlertInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alert_sender.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.sql_agent.agent_arn
}

resource "aws_bedrockagent_agent_action_group" "alert_action" {
  agent_id          = aws_bedrockagent_agent.sql_agent.agent_id
  agent_version     = "DRAFT"
  action_group_name = "metric_alert_group"

  action_group_executor {
    lambda = aws_lambda_function.alert_sender.arn
  }

  api_schema {
    payload = file("${path.module}/Alert_Action_Group.yaml")
  }

  depends_on = [aws_lambda_function.alert_sender]
}

############################################
# Bedrock Agent Role - add SES Lambda invoke
############################################

resource "aws_iam_role_policy" "bedrock_agent_alert_policy" {
  name = "bedrock-agent-alert-lambda-policy"
  role = aws_iam_role.bedrock_agent_role.id  # Attaches to your existing agent role

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeAlertLambda"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.alert_sender.arn
      }
    ]
  })
}

############################################
# Outputs
############################################

output "alert_lambda_arn" {
  value = aws_lambda_function.alert_sender.arn
}

output "ses_sender_identity" {
  value = aws_ses_email_identity.sender.arn
}

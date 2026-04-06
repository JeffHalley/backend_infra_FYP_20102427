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

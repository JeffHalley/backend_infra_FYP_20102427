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

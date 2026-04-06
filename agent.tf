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

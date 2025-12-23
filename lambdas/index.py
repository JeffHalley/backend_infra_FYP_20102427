import json
import os
import uuid
import boto3

# Initialize the Bedrock Runtime client
client = boto3.client('bedrock-agent-runtime', region_name='eu-west-1')

def lambda_handler(event, context):
    agent_id = os.environ.get('AGENT_ID')
    agent_alias_id = os.environ.get('AGENT_ALIAS_ID')
    
    print(f"Attempting to invoke Agent: {agent_id} with Alias: {agent_alias_id}")
    try:
        # 1. Parse input from React app
        body = json.loads(event.get('body', '{}'))
        user_prompt = body.get('prompt', 'Hello!')
        
        # 2. Invoke the Bedrock Agent
        response = client.invoke_agent(
            agentId=os.environ['AGENT_ID'],
            agentAliasId=os.environ['AGENT_ALIAS_ID'],
            sessionId=str(uuid.uuid4()), # Unique session for this request
            inputText=user_prompt
        )

        # 3. Process the streaming response
        completion = ""
        for event in response.get('completion', []):
            chunk = event.get('chunk')
            if chunk:
                completion += chunk.get('bytes').decode('utf-8')

        # 4. Return to frontend
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*' # Ensure CORS matches APIGW
            },
            'body': json.dumps({'response': completion})
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }
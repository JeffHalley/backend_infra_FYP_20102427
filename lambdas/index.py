import json
import os
import boto3

# Initialize clients
bedrock = boto3.client("bedrock-runtime", region_name="eu-west-1")
s3 = boto3.client("s3")

MODEL_ID = os.environ.get('MODEL_ID', 'amazon.nova-lite-v1:0')
BUCKET_NAME = os.environ.get('BUCKET_NAME')

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        
        # 1. Grab history and current prompt
        chat_history = body.get('messages', []) 
        user_prompt = body.get('prompt', '')

        # 2. Add current prompt to the history before calling Bedrock
        if user_prompt:
            chat_history.append({
                "role": "user",
                "content": [{"text": user_prompt}]
            })


        # 4. Define the Persona/Knowledge
        system_prompts = [{
            "text": f"You are a helpful assistant"
        }]

        # 5. Call Bedrock Converse API
        response = bedrock.converse(
            modelId=MODEL_ID,
            messages=chat_history,
            system=system_prompts,
            inferenceConfig={"maxTokens": 1000, "temperature": 0.7}
        )

        ai_text = response['output']['message']['content'][0]['text']
        
        # 6. Add AI response to history
        chat_history.append({
            "role": "assistant",
            "content": [{"text": ai_text}]
        })

        # 7. Return history and include CORS headers
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'response': ai_text,
                'history': chat_history 
            })
        }

    except Exception as e:
        print(f"CRITICAL ERROR: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
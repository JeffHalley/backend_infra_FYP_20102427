import json
import os
import boto3

# Bedrock client (standard model invocation, no agents)
bedrock = boto3.client("bedrock-runtime", region_name="eu-west-1")
s3 = boto3.client("s3")

# Load environment variables
BUCKET_NAME = os.environ['BUCKET_NAME']
MODEL_ID = os.environ.get('MODEL_ID', 'amazon.nova-lite-v1:0')

def lambda_handler(event, context):
    try:
        # 1. Parse user input from frontend
        body = json.loads(event.get('body', '{}'))
        user_prompt = body.get('prompt', '')

        # 2. Read all markdown files from S3
        md_objects = s3.list_objects_v2(Bucket=BUCKET_NAME)
        kb_text = ""

        for obj in md_objects.get('Contents', []):
            key = obj['Key']
            if key.endswith('.md'):
                file_obj = s3.get_object(Bucket=BUCKET_NAME, Key=key)
                content = file_obj['Body'].read().decode('utf-8')
                kb_text += f"\n\n### {key}\n{content}"

        # 3. Combine knowledge base + user prompt
        final_prompt = f"You are a helpful assistant. Use the following knowledge base context to answer the user.\n\n{kb_text}\n\nUser: {user_prompt}\nAssistant:"

        # 4. Invoke Bedrock model
        response = bedrock.invoke_model(
            modelId=MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "inputText": final_prompt,
                "maxTokens": 512
            })
        )

        # 5. Read model response
        result = json.loads(response['body'].read())
        completion = result.get('outputText', '')

        # 6. Return to frontend
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'response': completion})
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }
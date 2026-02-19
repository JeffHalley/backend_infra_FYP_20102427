import json
import os
import boto3

# Initialize clients
bedrock = boto3.client("bedrock-runtime", region_name="eu-west-1")
s3 = boto3.client("s3")
lambda_client = boto3.client("lambda")

MODEL_ID = os.environ.get('MODEL_ID', 'amazon.nova-lite-v1:0')
BUCKET_NAME = os.environ.get('BUCKET_NAME')
DB_LAMBDA_NAME = "bedrock-sql-db-conn"

def lambda_handler(event, context):
    print(f"DEBUG: Received event: {json.dumps(event)}")
    # API Gateway parses the JWT and puts the data here automatically
    user_id = event['requestContext']['authorizer']['jwt']['claims']['sub']
    
    # Use user_id as Partition Key for DynamoDB/Postgres queries
    print(f"Request from User: {user_id}")
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

        # 3. Read all markdown files from S3
        print(f"DEBUG: Fetching schema from S3 bucket: {BUCKET_NAME}")
        md_objects = s3.list_objects_v2(Bucket=BUCKET_NAME)
        kb_text = ""

        for obj in md_objects.get('Contents', []):
            key = obj['Key']
            if key.endswith('.md'):
                file_obj = s3.get_object(Bucket=BUCKET_NAME, Key=key)
                content = file_obj['Body'].read().decode('utf-8')
                kb_text += f"\n\n### {key}\n{content}"

        # 4. Define Persona
        sql_persona = f"""
        You are a specialized Text-to-SQL translator for a Postgres database. 

        <goal>
        Convert the user's natural language request into a single, valid, and runnable SQL query based ONLY on the provided schema context.
        </goal>

        <schema_context>
        {kb_text}
        </schema_context>

        <rules>
        1. ONLY return the raw SQL code.
        2. DO NOT include any introductory text (e.g., "Certainly!", "Here is the query").
        3. DO NOT include any explanations or markdown commentary.
        4. DO NOT use markdown code blocks (no ```sql).
        5. Ensure all table and column names match the <schema_context> exactly.
        6. If the request cannot be fulfilled by the schema, return: -- ERROR: Insufficient schema context.
        </rules>

        <output_format>
        Return the SQL string only.
        </output_format>
        """

        system_prompts = [{"text": sql_persona}]

        # 5. Call Bedrock Converse API
        print("DEBUG: Calling Bedrock Converse API...")
        response = bedrock.converse(
            modelId=MODEL_ID,
            messages=chat_history,
            system=system_prompts,
            inferenceConfig={"maxTokens": 1000, "temperature": 0.7}
        )

        ai_text = response['output']['message']['content'][0]['text'].strip()
        print(f"DEBUG: AI Generated SQL: {ai_text}")
        
        # 6. Call Database Lambda if SQL was generated successfully
        db_output = None
        if not ai_text.startswith("-- ERROR"):
            print(f"DEBUG: Attempting to invoke DB Lambda: {DB_LAMBDA_NAME}")
            try:
                db_response = lambda_client.invoke(
                    FunctionName=DB_LAMBDA_NAME,
                    InvocationType='RequestResponse',
                    Payload=json.dumps({"query": ai_text})
                )
                
                # Check for FunctionError (errors inside the child lambda)
                if 'FunctionError' in db_response:
                    error_payload = db_response['Payload'].read().decode()
                    print(f"ERROR: DB Lambda execution error: {error_payload}")
                    db_output = f"Error from DB Lambda: {error_payload}"
                else:
                    db_payload = json.loads(db_response['Payload'].read().decode())
                    db_output = db_payload.get('body')
                    print(f"DEBUG: DB Lambda success. Rows returned: {len(db_output) if isinstance(db_output, list) else 'N/A'}")
            
            except Exception as invoke_e:
                print(f"ERROR: Failed to invoke DB Lambda: {str(invoke_e)}")
                db_output = f"Invocation failed: {str(invoke_e)}"
        else:
            print("DEBUG: AI returned an error/refusal, skipping DB invocation.")

        # 7. Add AI response to history
        chat_history.append({
            "role": "assistant",
            "content": [{"text": ai_text}]
        })

        # 8. Return history and SQL data
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'response': ai_text,
                'db_data': db_output,
                'history': chat_history 
            })
        }

    except Exception as e:
        print(f"CRITICAL ERROR: {str(e)}")
        import traceback
        traceback.print_exc() # print the full stack trace to logs
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
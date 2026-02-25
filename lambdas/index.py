import json
import os
import boto3
from common_config import get_shared_schema
from tenant_logic import get_tenant_context

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
    user_id = event['requestContext']['authorizer']['claims']['sub']
    
    # Use user_id as Partition Key for DynamoDB/Postgres queries
    print(f"Request from User: {user_id}")
    try:
        body = json.loads(event.get('body', '{}'))
        
        # Extract chat history and user prompt from request
        chat_history = body.get('messages', []) 
        user_prompt = body.get('prompt', '')

        # Append current prompt to conversation history for context
        if user_prompt:
            chat_history.append({
                "role": "user",
                "content": [{"text": user_prompt}]
            })

        # Retrieve shared schema context (globally cached)
        print("DEBUG: Fetching shared schema context...")
        kb_text = get_shared_schema()
        
        # Retrieve tenant-specific context (isolated to user)
        print("DEBUG: Fetching tenant-specific context...")
        tenant_context = get_tenant_context(user_id)

        # Define SQL generation persona and constraints
        sql_persona = f"""
        You are a specialized Text-to-SQL translator for a Postgres database. 

        <goal>
        Convert the user's natural language request into a single, valid, and runnable SQL query based ONLY on the provided schema context.
        </goal>

        <schema_context>
        {kb_text}
        </schema_context>

        <critical_constraints>
        1. NEVER answer a question using your memory or previous assistant messages. 
        2. Even if the answer seems obvious from the chat history, you MUST generate a SQL query to fetch the data fresh.
        3. DO NOT summarize data. DO NOT explain metadata.
        4. YOU ARE NOT A CHATBOT. If your output contains a single English sentence, you have failed.
        </critical_constraints>

        <formatting_rules>
        1. OUTPUT ONLY THE RAW STRING. 
        2. NEVER use markdown code blocks like ```sql or ```. 
        3. NEVER use any markdown formatting.
        4. NO introductory text. NO closing remarks.
        </formatting_rules>

        <negative_examples>
        USER: "check metadata"
        WRONG: ```sql SELECT metadata... ```
        WRONG: "Here is the query: SELECT metadata..."
        RIGHT: SELECT metadata FROM public.metrics WHERE host_name = 'Interprd4697' ORDER BY time DESC LIMIT 1;
        </negative_examples>

        <rules>
        1. ONLY return the raw SQL code.
        2. Ensure all table and column names match the <schema_context> exactly.
        3. If the request cannot be fulfilled by the schema, return: -- ERROR: Insufficient schema context.
        </rules>

        <output_format>
        Return the SQL string only. No backticks. No markdown.
        </output_format>
        """

        system_prompts = [{"text": sql_persona}]

        # Generate SQL query using Bedrock Converse API
        print("DEBUG: Calling Bedrock Converse API...")
        response = bedrock.converse(
            modelId=MODEL_ID,
            messages=chat_history,
            system=system_prompts,
            inferenceConfig={"maxTokens": 1000, "temperature": 0.3}
        )

        ai_sql = response['output']['message']['content'][0]['text'].strip()
        print(f"DEBUG: AI Generated SQL: {ai_sql}")
        
        # Execute generated SQL query via database Lambda
        db_output = None
        if not ai_sql.startswith("-- ERROR"):
            try:
                db_response = lambda_client.invoke(
                    FunctionName=DB_LAMBDA_NAME,
                    InvocationType='RequestResponse',
                    Payload=json.dumps({"query": ai_sql})
                )
                
                if 'FunctionError' in db_response:
                    db_output = "Error executing the generated query."
                else:
                    db_payload = json.loads(db_response['Payload'].read().decode())
                    db_output = db_payload.get('body', [])
            
            except Exception as invoke_e:
                print(f"ERROR: DB Lambda Invoke failed: {str(invoke_e)}")
                db_output = "Database connection failed."


        # Append assistant response to conversation history
        chat_history.append({
            "role": "assistant",
            "content": [{"text": json.dumps(db_output)}]  # Convert list/dict to string for display
        })

        # Return response with generated SQL and conversation history
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*', 'Content-Type': 'application/json'},
            'body': json.dumps({
                'response': db_output, # UI displays this
                'db_data': db_output,
                'history': chat_history,
                'generated_sql': ai_sql
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
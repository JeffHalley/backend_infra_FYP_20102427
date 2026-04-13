import json
import boto3
from botocore.config import Config
from boto3.dynamodb.conditions import Key

bedrock_agent_runtime = boto3.client(
    "bedrock-agent-runtime",
    region_name="eu-west-1",
    config=Config(
        connect_timeout=10,
        read_timeout=120,
        retries={"max_attempts": 2}
    )
)

dynamodb = boto3.resource("dynamodb", region_name="eu-west-1")
table = dynamodb.Table("conversations")

AGENT_ID = "3XKSOQIYPV"
AGENT_ALIAS_ID = "VDBPCZNVGG"

HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json"
}

def lambda_handler(event, context):
    # HTTP API v2 uses rawPath, REST API v1 uses path
    path = event.get("rawPath") or event.get("path", "")
    ...

    if path == "/conversations":
        return handle_conversations(event)
    elif path == "/ask":
        return handle_ask(event)
    else:
        return {"statusCode": 404, "headers": HEADERS, "body": json.dumps({"error": "Not found"})}


def handle_ask(event):
    try:
        body = json.loads(event.get("body", "{}"))
        user_prompt = body.get("prompt", "")
        session_id = body.get("session_id", "")

        response = bedrock_agent_runtime.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS_ID,
            sessionId=session_id,
            inputText=user_prompt
        )

        full_answer = ""
        for chunk in response.get("completion", []):
            if "chunk" in chunk:
                full_answer += chunk["chunk"]["bytes"].decode("utf-8")

        return {
            "statusCode": 200,
            "headers": HEADERS,
            "body": json.dumps({"response": full_answer, "session_id": session_id})
        }

    except Exception as e:
        print(f"ERROR /ask: {type(e).__name__}: {str(e)}")
        return {"statusCode": 500, "headers": HEADERS, "body": json.dumps({"error": str(e)})}


def handle_conversations(event):
    method = event.get("httpMethod", "GET")

    try:
        if method == "GET":
            user_id = event.get("queryStringParameters", {}).get("userId", "")
            result = table.query(
                KeyConditionExpression=Key("userId").eq(user_id)
            )
            items = sorted(
                result.get("Items", []),
                key=lambda x: x.get("lastUpdated", ""),
                reverse=True
            )
            return {
                "statusCode": 200,
                "headers": HEADERS,
                "body": json.dumps({"conversations": items})
            }

        elif method == "POST":
            body = json.loads(event.get("body", "{}"))
            table.put_item(Item={
                "userId": body["userId"],
                "sessionId": body["sessionId"],
                "title": body.get("title", "Untitled"),
                "messages": body.get("messages", []),
                "lastUpdated": body.get("lastUpdated", "")
            })
            return {"statusCode": 200, "headers": HEADERS, "body": json.dumps({"ok": True})}

    except Exception as e:
        print(f"ERROR /conversations: {type(e).__name__}: {str(e)}")
        return {"statusCode": 500, "headers": HEADERS, "body": json.dumps({"error": str(e)})}
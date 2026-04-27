import json
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
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
AGENT_ALIAS_ID = "KIIESLQS6U"

HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json"
}


def respond(status_code, body):
    """Helper to build a consistent response."""
    return {
        "statusCode": status_code,
        "headers": HEADERS,
        "body": json.dumps(body)
    }


def lambda_handler(event, context):
    path = event.get("rawPath") or event.get("path", "")

    if path == "/conversations":
        return handle_conversations(event)
    elif path == "/ask":
        return handle_ask(event)
    else:
        return respond(404, {"error": "Not found"})


def handle_ask(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return respond(400, {"error": "Request body must be valid JSON"})

    # 400 validation
    prompt = body.get("prompt", "").strip()
    session_id = body.get("session_id", "").strip()

    errors = []
    if not prompt:
        errors.append("'prompt' is required and cannot be empty")
    if not session_id:
        errors.append("'session_id' is required and cannot be empty")
    if errors:
        return respond(400, {"error": "Bad request", "details": errors})

    try:
        response = bedrock_agent_runtime.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS_ID,
            sessionId=session_id,
            inputText=prompt
        )

        full_answer = ""
        for chunk in response.get("completion", []):
            if "chunk" in chunk:
                full_answer += chunk["chunk"]["bytes"].decode("utf-8")

        return respond(200, {"response": full_answer, "session_id": session_id})

    except ClientError as e:
        # Separate Bedrock-specific errors from generic 500s
        code = e.response["Error"]["Code"]
        print(f"ERROR /ask ClientError [{code}]: {e}")
        if code in ("ValidationException", "ResourceNotFoundException"):
            return respond(400, {"error": f"Bedrock agent error: {code}"})
        return respond(500, {"error": "Upstream service error"})

    except Exception as e:
        print(f"ERROR /ask: {type(e).__name__}: {e}")
        return respond(500, {"error": "Internal server error"})


def handle_conversations(event):
    method = event.get("requestContext", {}).get("http", {}).get("method") \
             or event.get("httpMethod", "GET")

    if method == "GET":
        return _get_conversations(event)
    elif method == "POST":
        return _post_conversation(event)
    else:
        return respond(405, {"error": f"Method {method} not allowed"})


def _get_conversations(event):
    # 400 validation
    params = event.get("queryStringParameters") or {}
    user_id = params.get("userId", "").strip()
    if not user_id:
        return respond(400, {"error": "'userId' query parameter is required"})

    try:
        result = table.query(
            KeyConditionExpression=Key("userId").eq(user_id)
        )
        items = sorted(
            result.get("Items", []),
            key=lambda x: x.get("lastUpdated", ""),
            reverse=True
        )
        return respond(200, {"conversations": items})

    except ClientError as e:
        print(f"ERROR GET /conversations ClientError: {e}")
        return respond(500, {"error": "Database error"})

    except Exception as e:
        print(f"ERROR GET /conversations: {type(e).__name__}: {e}")
        return respond(500, {"error": "Internal server error"})


def _post_conversation(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return respond(400, {"error": "Request body must be valid JSON"})

    # 400 validation
    errors = []
    user_id = body.get("userId", "").strip()
    session_id = body.get("sessionId", "").strip()

    if not user_id:
        errors.append("'userId' is required and cannot be empty")
    if not session_id:
        errors.append("'sessionId' is required and cannot be empty")

    messages = body.get("messages", [])
    if not isinstance(messages, list):
        errors.append("'messages' must be an array")

    if errors:
        return respond(400, {"error": "Bad request", "details": errors})

    try:
        table.put_item(Item={
            "userId": user_id,
            "sessionId": session_id,
            "title": body.get("title", "Untitled"),
            "messages": messages,
            "lastUpdated": body.get("lastUpdated", "")
        })
        return respond(200, {"ok": True})

    except ClientError as e:
        print(f"ERROR POST /conversations ClientError: {e}")
        return respond(500, {"error": "Database error"})

    except Exception as e:
        print(f"ERROR POST /conversations: {type(e).__name__}: {e}")
        return respond(500, {"error": "Internal server error"})
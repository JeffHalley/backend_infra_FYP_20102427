import json
import boto3
import logging
from datetime import datetime

ses = boto3.client("ses", region_name="eu-west-1")

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Config
SENDER_EMAIL    = "jeffhalley420@gmail.com"
RECIPIENT_EMAIL = "jeffhalley420@gmail.com"


# Email builder
def build_email(alerts: list[dict]) -> tuple[str, str]:
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    count = len(alerts)

    subject = f"[METRICS ALERT] {count} unhealthy metric{'s' if count > 1 else ''} reported - {now}"

    rows = ""
    for a in alerts:
        rows += f"""
        <tr>
            <td style="padding:8px;border:1px solid #ddd;">{a.get('host_name', 'N/A')}</td>
            <td style="padding:8px;border:1px solid #ddd;">{a.get('app_name', 'N/A')}</td>
            <td style="padding:8px;border:1px solid #ddd;">{a.get('assignment_group', 'N/A')}</td>
            <td style="padding:8px;border:1px solid #ddd;">{a.get('metric_name', 'N/A')}</td>
            <td style="padding:8px;border:1px solid #ddd;color:red;font-weight:bold;">{a.get('status', 'N/A')}</td>
            <td style="padding:8px;border:1px solid #ddd;">{a.get('value', 'N/A')}</td>
            <td style="padding:8px;border:1px solid #ddd;">{a.get('time', 'N/A')}</td>
        </tr>
        """

    html_body = f"""
    <html>
    <body style="font-family:Arial,sans-serif;padding:20px;">
        <h2 style="color:#c0392b;"> Metrics Alert - {now}</h2>
        <p>
            The following {count} unhealthy metric{'s were' if count > 1 else ' was'} identified
            during a query and flagged for your attention by the Metrics Monitoring Agent.
        </p>
        <table style="border-collapse:collapse;width:100%;">
            <thead>
                <tr style="background:#c0392b;color:white;">
                    <th style="padding:8px;border:1px solid #ddd;">Host</th>
                    <th style="padding:8px;border:1px solid #ddd;">App</th>
                    <th style="padding:8px;border:1px solid #ddd;">Team</th>
                    <th style="padding:8px;border:1px solid #ddd;">Metric</th>
                    <th style="padding:8px;border:1px solid #ddd;">Status</th>
                    <th style="padding:8px;border:1px solid #ddd;">Value</th>
                    <th style="padding:8px;border:1px solid #ddd;">Time</th>
                </tr>
            </thead>
            <tbody>
                {rows}
            </tbody>
        </table>
        <p style="color:#888;font-size:12px;margin-top:20px;">
            This alert was requested by a user of the Metrics Monitoring Agent at {now}.
        </p>
    </body>
    </html>
    """

    return subject, html_body


def lambda_handler(event, context):
    logger.info(f"Received event: {event}")

    try:
        properties = event['requestBody']['content']['application/json']['properties']

        alerts = []
        for prop in properties:
            if prop.get("name") == "alerts":
                alerts = json.loads(prop.get("value", "[]"))
                break

        if not alerts:
            return _response(event, 400, {"message": "No alerts provided."})

        subject, html_body = build_email(alerts)

        ses.send_email(
            Source=SENDER_EMAIL,
            Destination={"ToAddresses": [RECIPIENT_EMAIL]},
            Message={
                "Subject": {"Data": subject},
                "Body":    {"Html": {"Data": html_body}},
            },
        )

        return _response(event, 200, {
            "message": f"Alert email sent successfully for {len(alerts)} unhealthy metric(s)."
        })

    except Exception as e:
        logger.exception(f"Error in lambda_handler: {str(e)}")
        return _response(event, 500, {"message": f"Failed to send alert: {str(e)}"})


# Bedrock response format
def _response(event, http_status_code, body):
    action_response = {
        'actionGroup':      event['actionGroup'],
        'apiPath':          event['apiPath'],
        'httpMethod':       event['httpMethod'],
        'httpStatusCode':   http_status_code,
        'responseBody': {
            'application/json': {
                'body': body if http_status_code == 200 else {
                    'error':   'REQUEST_FAILED',
                    'message': body.get('message', 'Unknown error')
                }
            }
        }
    }

    return {'messageVersion': '1.0', 'response': action_response}
import os
import psycopg2
import json
import re
import logging

from utils import create_api_response, get_error_response, get_property_value


logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_db_connection():
    """Helper to establish Postgres connection."""
    return psycopg2.connect(
        host=os.environ['DB_HOST'],
        database=os.environ['DB_NAME'],
        user=os.environ['DB_USER'],
        password=os.environ['DB_PASS'],
        connect_timeout=5
    )

def lambda_handler(event, context):
    logger.info(f"Received event: {event}")

    try:
        # 1. Extract properties following the Bedrock Action Group structure
        properties = event['requestBody']['content']['application/json']['properties']
        
        # 2. Get the query using utility
        query = get_property_value(
            properties,
            'query',
            'MISSING_QUERY',
            'QUERY',
            event
        )

        # 3. Handle query preprocessing if necessary
        if isinstance(query, dict):
            query = preprocess_query(query)
            # If preprocessing returns a full response object, return it
            if isinstance(query, dict) and 'actionGroup' in str(query):
                return query

        logger.info(f"Executing Postgres query: {query}")

        # 4. Execute the query against Postgres
        result = execute_postgres_query(query)

        # 5. Handle potential execution errors
        if isinstance(result, str) and "Error:" in result:
            return create_api_response(
                event,
                400,
                get_error_response('QUERY_EXECUTION_FAILED')
            )

        # 6. Return successful Bedrock Action Group response
        return create_api_response(event, 200, result)

    except Exception as e:
        logger.exception(f"Error in lambda_handler: {str(e)}")
        return create_api_response(
            event,
            500,
            {
                'error': 'INTERNAL_ERROR',
                'message': str(e),
                'hint': 'Check DB connectivity and query syntax.'
            }
        )

def execute_postgres_query(query):
    """Executes SQL and returns a list of dictionaries (rows)."""
    conn = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(query)
        
        columns = [desc[0] for desc in cur.description]
        rows = cur.fetchall()
        
        results = []
        for row in rows:
            clean_row = [val.isoformat() if hasattr(val, 'isoformat') else val for val in row]
            results.append(dict(zip(columns, clean_row)))
        
        cur.close()
        return results
    except Exception as e:
        return f"Error: {str(e)}"
    finally:
        if conn:
            conn.close()

def preprocess_query(query):
    """Mirroring the date logic from the Athena sample."""
    # Note: Postgres handles 'YYYY-MM-DD' literals well, but keep the logic for parity
    date_pattern = r"(datetime|date)\s+BETWEEN\s+'(\d{4}-\d{2}-\d{2})'\s+AND\s+'(\d{4}-\d{2}-\d{2})'"
    match = re.search(date_pattern, query, re.IGNORECASE)

    if match:
        column, start_date, end_date = match.groups()
        modified_query = query.replace(
            f"{column} BETWEEN '{start_date}' AND '{end_date}'",
            f"{column} BETWEEN '{start_date}'::timestamp AND '{end_date}'::timestamp"
        )
        return modified_query

    return query
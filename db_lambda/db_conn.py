import os
import psycopg2
import json

def lambda_handler(event, context):
    # Extract the query from the event passed by the Main Lambda
    query = event.get('query')
    
    if not query:
        return {
            'statusCode': 400,
            'body': "No SQL query provided in event payload."
        }

    try:
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            database=os.environ['DB_NAME'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASS'],
            connect_timeout=5
        )
        cur = conn.cursor()

        # Run the AI-generated query
        cur.execute(query)
        
        # Fetch results and map to column names for a cleaner JSON output
        columns = [desc[0] for desc in cur.description]
        rows = cur.fetchall()
        
        results = []
        for row in rows:
            results.append(dict(zip(columns, row)))

        cur.close()
        conn.close()

        return {
            'statusCode': 200,
            'body': results
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': f"Database query failed: {str(e)}"
        }
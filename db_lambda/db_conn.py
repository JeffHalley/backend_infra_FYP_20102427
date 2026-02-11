import os
import psycopg2

def lambda_handler(event, context):
    try:
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            database=os.environ['DB_NAME'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASS'],
            connect_timeout=5
        )
        cur = conn.cursor()

        # 1. Get a list of all user-created tables
        cur.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public';
        """)
        tables = [row[0] for row in cur.fetchall()]

        # 2. Peek into the first table found (if any exist)
        peek_data = "No tables found."
        if tables:
            target_table = tables[0]
            # Fetch the first 3 rows
            cur.execute(f'SELECT * FROM "{target_table}" LIMIT 3;')
            rows = cur.fetchall()
            peek_data = f"Rows from {target_table}: {rows}"

        cur.close()
        conn.close()

        return {
            'statusCode': 200,
            'body': {
                "status": "Success",
                "detected_tables": tables,
                "data_preview": peek_data
            }
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': f"Database query failed: {str(e)}"
        }
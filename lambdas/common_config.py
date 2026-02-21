import boto3
import os

s3 = boto3.client("s3")
BUCKET_NAME = os.environ.get('BUCKET_NAME')

# GLOBAL CACHE - Shared by all users hitting THIS specific environment
CACHED_SCHEMA = None

def get_shared_schema():
    global CACHED_SCHEMA
    if CACHED_SCHEMA:
        print("DEBUG: skipping s3 lookup. Returning Shared Schema from Global Cache.")
        return CACHED_SCHEMA

    print("DEBUG: Global Cache Miss. Fetching Shared Schema from S3.")
    md_objects = s3.list_objects_v2(Bucket=BUCKET_NAME)
    kb_text = ""
    for obj in md_objects.get('Contents', []):
        if obj['Key'].endswith('.md'):
            content = s3.get_object(Bucket=BUCKET_NAME, Key=obj['Key'])['Body'].read().decode('utf-8')
            kb_text += f"\n### {obj['Key']}\n{content}"
    
    CACHED_SCHEMA = kb_text
    return CACHED_SCHEMA
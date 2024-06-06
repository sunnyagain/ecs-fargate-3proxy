import boto3
import os

efs_client = boto3.client('efs')
s3_client = boto3.client('s3')

EFS_FILE_SYSTEM_ID = os.environ['EFS_FILE_SYSTEM_ID']
S3_BUCKET = os.environ['S3_BUCKET']
S3_KEY = os.environ['S3_KEY']

def handler(event, context):
    
    # Download the file from S3
    local_file_path = os.path.join('/mnt/efs', '3proxy.cfg')
    s3_client.download_file(S3_BUCKET, S3_KEY, local_file_path)
    
    return {
        'statusCode': 200,
        'body': 'File synced successfully'
    }


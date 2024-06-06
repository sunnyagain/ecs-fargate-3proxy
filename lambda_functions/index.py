import boto3
import os
from datetime import datetime
import json

ecs = boto3.client('ecs')

def start_handler(event, context):
    cluster = os.environ['ECS_CLUSTER']
    service = os.environ['ECS_SERVICE']
    response = ecs.update_service(
        cluster=cluster,
        service=service,
        desiredCount=1
    )
    response['ResponseMetadata']['HTTPHeaders']['date'] = response['ResponseMetadata']['HTTPHeaders']['date'].strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }

def stop_handler(event, context):
    cluster = os.environ['ECS_CLUSTER']
    service = os.environ['ECS_SERVICE']
    response = ecs.update_service(
        cluster=cluster,
        service=service,
        desiredCount=0
    )
    response['ResponseMetadata']['HTTPHeaders']['date'] = response['ResponseMetadata']['HTTPHeaders']['date'].strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }
import boto3
import os
from datetime import datetime
import json

ecs = boto3.client('ecs')

def start_handler(event, context):
    cluster = os.environ['ECS_CLUSTER']
    service = os.environ['ECS_SERVICE']
    response = ecs.update_service(
        cluster=cluster,
        service=service,
        desiredCount=1
    )
    response = convert_datetime_to_string(response)
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }

def stop_handler(event, context):
    cluster = os.environ['ECS_CLUSTER']
    service = os.environ['ECS_SERVICE']
    desiredCount = 0
    response = ecs.update_service(
        cluster=cluster,
        service=service,
        desiredCount=desiredCount
    )
    response = convert_datetime_to_string(response)
    return {
        'statusCode': 200,
        'body': json.dumps(response)
    }

def convert_datetime_to_string(data):
    if isinstance(data, dict):
        for key, value in data.items():
            if isinstance(value, datetime):
                data[key] = value.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
            elif isinstance(value, dict):
                data[key] = convert_datetime_to_string(value)
            elif isinstance(value, list):
                data[key] = [convert_datetime_to_string(item) if isinstance(item, (dict, datetime)) else item for item in value]
    elif isinstance(data, list):
        data = [convert_datetime_to_string(item) if isinstance(item, (dict, datetime)) else item for item in data]
    return data

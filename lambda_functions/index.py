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

def dns_handler(event, context):
    ecs_client = boto3.client('ecs')
    r53_client = boto3.client('route53')
    
    cluster = os.environ['ECS_CLUSTER']
    service = os.environ['ECS_SERVICE']
    hosted_zone_id = os.environ['HOSTED_ZONE_ID']
    record_name = os.environ['RECORD_NAME']
    
    # Get the latest task details
    tasks = ecs_client.list_tasks(cluster=cluster, serviceName=service)
    task_arn = tasks['taskArns'][0]
    task_details = ecs_client.describe_tasks(cluster=cluster, tasks=[task_arn])
    eni_id = task_details['tasks'][0]['attachments'][0]['details'][1]['value']
    
    # Get the public IP of the ENI
    ec2_client = boto3.client('ec2')
    eni = ec2_client.describe_network_interfaces(NetworkInterfaceIds=[eni_id])
    public_ip = eni['NetworkInterfaces'][0]['Association']['PublicIp']
    
    # Update the Route 53 DNS record
    response = r53_client.change_resource_record_sets(
        HostedZoneId=hosted_zone_id,
        ChangeBatch={
            'Comment': 'Update record to reflect new ECS task IP',
            'Changes': [
                {
                    'Action': 'UPSERT',
                    'ResourceRecordSet': {
                        'Name': record_name,
                        'Type': 'A',
                        'TTL': 60,
                        'ResourceRecords': [{'Value': public_ip}]
                    }
                }
            ]
        }
    )
    
    return {
        'statusCode': 200,
        'body': f'Updated DNS record to point to {public_ip}'
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

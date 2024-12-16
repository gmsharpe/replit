import boto3
from time import sleep
import cfnresponse
from botocore.exceptions import ClientError, WaiterError

cfn = boto3.client("cloudformation")

def handler(event, context):
    try:
        request_type = event['RequestType']
        if request_type == 'Delete':
            buckets = [
                event['ResourceProperties']['CODEBUCKET'],
                event['ResourceProperties']['ARTIFACTBUCKET'],
                event['ResourceProperties']['TRAILBUCKET'],
                event['ResourceProperties']['DATABUCKET']
            ]

            for bucket_name in buckets:
                bucket = boto3.resource("s3").Bucket(bucket_name)
                bucket.object_versions.delete()
                bucket.objects.all().delete()

            deploy_stack_name = "${local.stack_name}-deploy-${var.environment_name}"
            ingest_stack_name = "${local.stack_name}-data-ingestion-deploy-${var.environment_name}"

            for stack_name in [ingest_stack_name, deploy_stack_name]:
                try:
                    cfn.delete_stack(StackName=stack_name)
                    print(f"Waiting for stack {stack_name} to be deleted...")
                    waiter = cfn.get_waiter('stack_delete_complete')
                    waiter.wait(StackName=stack_name)
                    print(f"Stack {stack_name} successfully deleted.")
                except WaiterError as e:
                    print(f"Error waiting for stack {stack_name} deletion: {str(e)}")
                    cfnresponse.send(event, context, cfnresponse.FAILED, {})
                    return

        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as ex:
        print(f"Unexpected error: {ex}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
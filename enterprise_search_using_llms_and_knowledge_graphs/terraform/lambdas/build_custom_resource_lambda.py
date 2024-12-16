import boto3
from time import sleep
import cfnresponse

codebuild = boto3.client("codebuild")

def handler(event, context):
    try:
        request_type = event['RequestType']
        print("request_type", request_type)

        if request_type == 'Create':
            status = 'STARTING'
            print("status", event)
            build_id = codebuild.start_build(projectName=event['ResourceProperties']['PROJECT'])['build']['id']

            while status not in ['SUCCEEDED', 'FAILED', 'STOPPED', 'FAULT', 'TIMED_OUT']:
                status = codebuild.batch_get_builds(ids=[build_id])['builds'][0]['buildStatus']
                sleep(15)

            if status in ['FAILED', 'STOPPED', 'FAULT', 'TIMED_OUT']:
                print("Initial CodeBuild failed")
                cfnresponse.send(event, context, cfnresponse.FAILED, {})
                return

        elif request_type == 'Delete':
            bucket = boto3.resource("s3").Bucket(event['ResourceProperties']['CODEBUCKET'])
            bucket.object_versions.delete()
            bucket.objects.all().delete()

    except Exception as ex:
        print(ex)
        bucket = boto3.resource("s3").Bucket(event['ResourceProperties']['CODEBUCKET'])
        bucket.object_versions.delete()
        bucket.objects.all().delete()
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
    else:
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
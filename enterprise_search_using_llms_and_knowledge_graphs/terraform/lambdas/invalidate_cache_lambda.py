import json
import boto3
import zipfile
import os

code_pipeline = boto3.client("codepipeline")
cloud_front = boto3.client("cloudfront")
s3 = boto3.client('s3')

def get_input_artifacts(inputArtifacts):
  bucketName = inputArtifacts["location"]["s3Location"]["bucketName"]
  objectKey = inputArtifacts["location"]["s3Location"]["objectKey"]

  s3.download_file(bucketName, objectKey, "/tmp/file.zip")

  with zipfile.ZipFile("/tmp/file.zip", 'r') as zip_ref:
      zip_ref.extractall("/tmp/extracted")

  json_file_path = os.path.join("/tmp/extracted", 'CreateStackOutput.json')
  with open(json_file_path, 'r') as json_file:
      json_data = json.loads(json_file.read())
      # You can now use json_data as needed
  return json_data["CloudfrontID"]


def handler(event, context):
    job_id = event["CodePipeline.job"]["id"]
    try:
        CloudfrontID = get_input_artifacts(event["CodePipeline.job"]["data"]["inputArtifacts"][0])

        cloud_front.create_invalidation(
            DistributionId=CloudfrontID,
            InvalidationBatch={
                "Paths": {
                    "Quantity": 1,
                    "Items": ["/*"],
                },
                "CallerReference": event["CodePipeline.job"]["id"],
            },
        )
    except Exception as e:
        code_pipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                "type": "JobFailed",
                "message": str(e),
            },
        )
    else:
        code_pipeline.put_job_success_result(
            jobId=job_id,
        )
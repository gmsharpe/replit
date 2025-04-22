import json
import sys
import boto3
import requests
from requests.auth import AuthBase
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import get_credentials
from botocore.session import get_session

# ---------- CONFIGURABLE VALUES ----------
# Set the Lambda function URL from python args

FUNCTION_URL = "https://kzxdvs3apwfd6nle5ab2qqbpoa0eogia.lambda-url.us-west-2.on.aws/"
REGION = "us-west-2"
QUERY = "What models are available in Amazon Bedrock?"
MODEL = "anthropic.claude-instant-v1"
STREAMING_FORMAT = "fetch-event-source"
# ----------------------------------------

# You can override with CLI args: python invoke_lambda_streaming.py <function_url>
if len(sys.argv) > 1:
    FUNCTION_URL = sys.argv[1]

# Prepare payload
payload = {
    "query": QUERY,
    "model": MODEL,
    "streamingFormat": STREAMING_FORMAT
}

# Create a SigV4-signed request
session = get_session()
credentials = session.get_credentials()
region = REGION
service = "lambda"

request = AWSRequest(method="POST", url=FUNCTION_URL, data=json.dumps(payload), headers={
    "Host": FUNCTION_URL.split("//")[1].split("/")[0],
    "Content-Type": "application/json"
})

SigV4Auth(credentials, service, region).add_auth(request)
signed_headers = dict(request.headers)

# Send request using `requests`, stream the response
try:
    response = requests.post(
        FUNCTION_URL,
        headers=signed_headers,
        data=json.dumps(payload),
        stream=True
    )
    print(f"Status: {response.status_code}\n")
    for line in response.iter_lines():
        if line:
            print(line.decode("utf-8"))
except Exception as e:
    print("Error invoking Lambda:", e)

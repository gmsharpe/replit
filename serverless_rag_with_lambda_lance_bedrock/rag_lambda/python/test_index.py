import asyncio
import os
import json
from io import StringIO

import pytest

from index import handler
import logging

# Set environment variables
os.environ["s3BucketName"] = "streaming-rag-on-lambda-documents-us-west-2-${account_id}"
os.environ["lanceDbTable"] = "doc_table"
os.environ["region"] = "us-west-2"  # Change to your region

# Verify they are set correctly
print(f"s3BucketName: {os.getenv('s3BucketName')}")
print(f"lanceDbTable: {os.getenv('lanceDbTable')}")
print(f"region: {os.getenv('region')}")

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

#os.environ['PYTHONUNBUFFERED'] = '1'

class MockResponseStream:
    def __init__(self):
        self.output = StringIO()

    def write(self, data):
        #print(data, end="", flush=True)  # Print response
        self.output.write(data)

    def end(self):
        self.output.write("\n[Response stream closed]")
        #print("\n[Response stream closed]")

    def get_output(self):
        # Reset the pointer to the beginning before reading
        self.output.seek(0)
        return self.output.read()

async def test_handler():
    event = {
        "body": json.dumps({
            "query": "Tell me about the US health care system",
            "model": "anthropic.claude-instant-v1",
            "streamingFormat": None # "fetch-event-source"
        }),
        "isBase64Encoded": False
    }

    response_stream = MockResponseStream()
    await handler(event, response_stream, None)
    output = response_stream.get_output()
    print("Final Output:\n\n", output)


@pytest.mark.asyncio
async def main():
    await test_handler()

# Run the test
asyncio.run(main())

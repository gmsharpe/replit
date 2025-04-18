import json
import os

import boto3
from lancedb import connect_async
from langchain_aws import BedrockEmbeddings, ChatBedrockConverse
from langchain_community.vectorstores import LanceDB
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import PromptTemplate
from langchain_core.prompts.base import format_document

os.environ["s3BucketName"] = "streaming-rag-on-lambda-documents-"
os.environ["lanceDbTable"] = "doc_table"
os.environ["region"] = "us-west-2"

# Environment variables
lance_db_src = os.getenv('s3BucketName')
lance_db_table = os.getenv('lanceDbTable')
aws_region = os.getenv('region')


def format_documents_as_string(docs):
    prompt = PromptTemplate.from_template("Page {page}: {page_content}")
    return "\n".join(format_document(doc, prompt) for doc in docs)


async def run_chain(query, model, streaming_format, response_stream):
    credentials = assume_limited_role("document-processor-role", region=aws_region)

    storage_options = {
        "aws_region": aws_region,
        "aws_access_key_id": credentials['AccessKeyId'],
        "aws_secret_access_key": credentials['SecretAccessKey'],
        "aws_session_token": credentials['SessionToken']
    }

    db = await connect_async(f's3://{lance_db_src}/', storage_options=storage_options)

    # print tables
    tables = await db.table_names()
    print('Tables:', tables)

    table = await db.open_table(lance_db_table)

    print('query', query)
    print('model', model)
    print('streaming_format', streaming_format)

    embeddings = BedrockEmbeddings()
    vector_store = LanceDB(embedding=embeddings, uri=f's3://{lance_db_src}/', table_name=lance_db_table, connection=db)
    retriever = vector_store.as_retriever()

    prompt = PromptTemplate.from_template(
        """Answer the following question based only on the following context:
        {context}

        Question: {question}"""
    )

    # https://python.langchain.com/api_reference/aws/chat_models/langchain_aws.chat_models.bedrock_converse.ChatBedrockConverse.html
    llm_model = ChatBedrockConverse(
        model=model or 'anthropic.claude-instant-v1',
        region_name=aws_region,
        max_tokens=2000,
    )

    chain = (
            retriever.pipe(format_documents_as_string) |
            (lambda docs: {'context': docs, 'question': query}) |
            prompt |
            llm_model |
            StrOutputParser()
    )

    # https://python.langchain.com/docs/how_to/streaming/
    stream = chain.astream(query)
    chunks = []
    async for chunk in stream:
        if streaming_format == 'fetch-event-source':
            chunks.append(chunk)
            response_stream.write(f'event: message\n')
            response_stream.write(f'data: {chunk}')
            response_stream.write('\n\n')
        else:
            chunks.append(chunk)
            response_stream.write(chunk)
    response_stream.end()
    return chunks


def parse_base64(message):
    import base64
    import json
    return json.loads(base64.b64decode(message).decode('utf-8'))


async def lambda_handler(event, response_stream, _context):
    print(json.dumps(event))
    body = parse_base64(event['body']) if event.get('isBase64Encoded') else json.loads(event['body'])
    chunks = await run_chain(body['query'], body.get('model'), body.get('streamingFormat'), response_stream)
    # not currently doing anything with the chunks[] here.
    print(json.dumps({"status": "complete"}))


def assume_limited_role(role_name, region='us-west-2'):
    """
        Assume a role with limited permissions to interact with the S3 bucket.

    :return: Temporary credentials for the assumed role.
    """
    sts_client = boto3.client('sts', region_name=region)
    caller_identity = sts_client.get_caller_identity()
    account_id = caller_identity.get('Account')

    try:
        assumed_role_object = sts_client.assume_role(
            RoleArn=f'arn:aws:iam::{account_id}:role/{role_name}',
            RoleSessionName='LanceDBSession'
        )
        credentials = assumed_role_object['Credentials']
        print("Assumed role and obtained temporary credentials.")
    except Exception as e:
        print(f"Error assuming role: {e}")
        raise

    return credentials


# Sample events
sample_event_1 = {
    "query": "What models are available in Amazon Bedrock?",
}

sample_event_2 = {
    "query": "What models are available in Amazon Bedrock?",
    "model": "anthropic.claude-instant-v1"
}

sample_event_3 = {
    "query": "What models are available in Amazon Bedrock?",
    "model": "anthropic.claude-v2",
    "streamingFormat": "fetch-event-source"
}

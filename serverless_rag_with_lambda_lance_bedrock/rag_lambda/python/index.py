import os

from lancedb import connect, connect_async
from langchain.chat_models import ChatBedrock
from langchain.embeddings import BedrockEmbeddings
from langchain.utilities import awslambda
from langchain.vectorstores import LanceDB
from langchain_core.output_parsers import StrOutputParser

from langchain_core.prompts import PromptTemplate
from langchain_core.prompts.base import format_document
from langchain_core.runnables import RunnableSequence, RunnableMap, RunnablePassthrough

# Environment variables
lance_db_src = os.getenv('s3BucketName')
lance_db_table = os.getenv('lanceDbTable')
aws_region = os.getenv('region')

def format_documents_as_string(docs):
    prompt = PromptTemplate.from_template("Page {page}: {page_content}")
    return "\n".join(format_document(doc, prompt) for doc in docs)

async def run_chain(query, model, streaming_format, response_stream):
    db = await connect_async(f's3://{lance_db_src}/')
    table = await db.open_table(lance_db_table)
    print('query', query)
    print('model', model)
    print('streaming_format', streaming_format)

    embeddings = BedrockEmbeddings(region=aws_region)
    vector_store = LanceDB(embeddings, table=table)
    retriever = vector_store.as_retriever()

    prompt = PromptTemplate.from_template(
        """Answer the following question based only on the following context:
        {context}

        Question: {question}"""
    )

    llm_model = ChatBedrock(
        model=model or 'anthropic.claude-instant-v1',
        region=aws_region,
        streaming=True,
        max_tokens=1000,
    )

    chain = RunnableSequence.from_runnables([
        RunnableMap({
            'context': retriever.pipe(format_documents_as_string),
            'question': RunnablePassthrough()
        }),
        prompt,
        llm_model,
        StrOutputParser()
    ])


    stream = await chain.astream(query)
    async for chunk in stream:
        print(chunk)
        if streaming_format == 'fetch-event-source':
            response_stream.write(f'event: message\n')
            response_stream.write(f'data: {chunk}\n\n')
        else:
            response_stream.write(chunk)
    response_stream.end()

def parse_base64(message):
    import base64
    import json
    return json.loads(base64.b64decode(message).decode('utf-8'))

@awslambda.streamify_response
async def handler(event, response_stream, _context):
    import json
    print(json.dumps(event))
    body = parse_base64(event['body']) if event.get('isBase64Encoded') else json.loads(event['body'])
    await run_chain(body['query'], body.get('model'), body.get('streamingFormat'), response_stream)
    print(json.dumps({"status": "complete"}))

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

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import os

import boto3
from langchain_text_splitters import CharacterTextSplitter
from langchain_community.vectorstores import LanceDB
import lancedb as ldb
from langchain_aws import BedrockEmbeddings
from langchain_community.document_loaders.pdf import PyPDFDirectoryLoader


import pyarrow as pa
embeddings = BedrockEmbeddings(model_id="amazon.titan-embed-text-v2:0", region_name="us-west-2")


# we split the data into chunks of 1,000 characters, with an overlap
# of 200 characters between the chunks, which helps to give better results
# and contain the context of the information between chunks
text_splitter = CharacterTextSplitter(chunk_size=1000, chunk_overlap=200)

db = ldb.connect('tmp/embeddings')

schema = pa.schema(
  [
      pa.field("vector", pa.list_(pa.float32(), 1536)), # document vector with 1.5k dimensions (TitanEmbedding)
      pa.field("text", pa.string()), # langchain requires it
      pa.field("id", pa.string()) # langchain requires it
  ])

tbl = db.create_table("doc_table", schema=schema, exist_ok=True)

# load the document as before

loader = PyPDFDirectoryLoader("./docs/")

docs = loader.load()
docs = text_splitter.split_documents(docs)


# Update LanceDB storage configuration
LanceDB.from_documents(docs, embeddings, uri='tmp/embeddings/doc_table/', table_name="doc_table")

s3_bucket_name = "streaming-rag-on-lambda-documents-us-west-2-736682772784"
LanceDB.from_documents(docs, embeddings, uri='s3://' + s3_bucket_name + '/doc_table/', table_name="doc_table")

# sync folder with S3
#boto3.client('s3').upload_file('tmp/embeddings', 's3://' + s3_bucket_name + '/doc_table/' , 'embeddings.parquet')

print("woop woop")
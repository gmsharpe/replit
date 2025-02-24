# pip install llama-index llama-index-embeddings-huggingface llama-index-readers-web llama-index-vector-stores-lancedb diffusers huggingface-hub -q
import os

# adopted from https://colab.research.google.com/github/lancedb/vectordb-recipes/blob/main/tutorials/RAG-with_MatryoshkaEmbed-Llamaindex/RAG_with_MatryoshkaEmbedding_and_Llamaindex.ipynb#scrollTo=hgVHOEBZ2lS5

from llama_index.core import VectorStoreIndex, Settings, StorageContext
from llama_index.core.ingestion import IngestionPipeline
from llama_index.vector_stores.lancedb import LanceDBVectorStore
from llama_index.llms.openai import OpenAI
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
import lancedb
import asyncio

from data_utils import chunk_documents, time_block, download_pdfs, pdf_urls
from lance_vector_database_on_s3.data_utils import crawl_lancedb_guides
from setup import assume_limited_role


def connect(db_uri, credentials):
    try:
        db = lancedb.connect(
            db_uri,
            storage_options={
                "timeout": "60s",
                "aws_region": "us-west-1",
                "aws_access_key_id": credentials['AccessKeyId'],
                "aws_secret_access_key": credentials['SecretAccessKey'],
                "aws_session_token": credentials['SessionToken'], }
        )
        print("Connected to LanceDB.")
    except Exception as e:
        print(f"Error connecting to LanceDB: {e}")
        raise

    return db


def build_RAG(
        input_data_dir, db,
        table_name
):
    """
    This function sets embedding model, llm, and vector store to be used for creating RAG index.
    If changes are detected in the input data directory, the vector store is cleared and recreated.
    """

    # Set the language model
    Settings.llm = OpenAI()  # Uses API key from the environment

    # Check if a LanceDB connection is provided
    if db is None:
        raise ValueError("A valid LanceDB connection (`db`) must be provided.")

    # Initialize the LanceDBVectorStore
    vector_store = LanceDBVectorStore(uri=db_uri, table_name=table_name)

    # Initialize storage context
    storage_context = StorageContext.from_defaults(vector_store=vector_store)

    changes, documents = chunk_documents(input_data_dir)
    # Check for changes in the input data directory
    if changes:  # changes_detected(input_data_dir):
        # If changes are detected, clear the vector store
        print("Changes detected in the input data. Clearing and recreating the vector store.")
        tables = db.table_names()
        if table_name in tables:
            table = db.open_table(table_name)
            table.delete("1=1")  # Clear the LanceDB table
            print(f"Cleared the '{table_name}' table.")
        # Recreate the index from the documents
        with (time_block("VectorStoreIndex creation")):

            pipeline = IngestionPipeline(
                transformations=Settings.transformations
            )
            async def run_pipeline():
                return await pipeline.arun(documents=documents, num_workers=12, show_progress=True)

            nodes = asyncio.run(run_pipeline())

            index = VectorStoreIndex(nodes=nodes, storage_context=storage_context, show_progress=True)
            print("Index created.")
            # index = VectorStoreIndex.from_documents(documents,
            #                                         storage_context=storage_context,
            #                                         show_progress=True)
    else:
        # Use the existing vector store if no changes are detected
        print("Data should already be vectorized and stored in the database, but the hash depends only on changes detected 'locally'.")
        index = VectorStoreIndex.from_vector_store(vector_store)

    tables = db.table_names()
    print("Tables in the database:", tables)

    # Create the query engine from the index
    query_engine = index.as_chat_engine()

    return query_engine


def interactive_session():
    print("Ask a question relevant to the given context:")
    while True:
        query = input("Query: ")
        response = query_engine.chat(query)
        print("Response:", response)
        if query == "exit":
            break


if __name__ == "__main__":
    with time_block("Creating AWS Resources"):
        # Unique name for your project
        #   (also used for s3 bucket so no spaces or underscores)
        project_id = ""
        policy_name = 'LanceDBS3AccessPolicy' + project_id
        role_name = 'LanceDBS3AccessRole' + project_id

        bucket_name = project_id + 'lancedb-on-s3'

        #setup_cloud_resources(bucket_name, role_name, policy_name, region='us-west-1')
        credentials = assume_limited_role(role_name, region='us-west-1')

        input_data_dir = "data"
        if not os.path.exists(input_data_dir):
            os.makedirs(input_data_dir)

        # set this to True when ready to use the Gale Encyclopedia of Medicine PDFs
        using_gale_encyclopedia_of_medicine = False

        if using_gale_encyclopedia_of_medicine:
            db_name = "gale-encyclopedia-of-medicine"
            if os.path.exists(input_data_dir + "/document_1.pdf"):
                print("PDFs already downloaded.")
            else:
                print("Downloading PDFs...")
                with time_block("Download Gale Encyclopedia of Medicine PDFs"):
                    download_pdfs(pdf_urls)
        else:
            db_name = "lancedb-docs"
            with time_block("Crawl LanceDB Docs"):
                asyncio.run(crawl_lancedb_guides())


        db_uri = f"s3://{bucket_name}/{db_name}/"
        embedding_model = "tomaarsen/mpnet-base-nli-matryoshka"
        matryoshka_embedding_size = 256

        # Set the embedding model
        #Settings.embed_model = OpenAIEmbedding(model="text-embedding-3-small")
        Settings.embed_model = HuggingFaceEmbedding(
            model_name=embedding_model,  # matryoshka_embedding_model,
            truncate_dim=int(matryoshka_embedding_size),
        )

        db = connect(db_uri, credentials)

        query_engine = build_RAG(
            input_data_dir, db,
            table_name=db_name # also database name
        )

        interactive_session()

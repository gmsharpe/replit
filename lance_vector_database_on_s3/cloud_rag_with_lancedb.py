# pip install llama-index llama-index-embeddings-huggingface llama-index-readers-web llama-index-vector-stores-lancedb diffusers huggingface-hub -q
import os

# adopted from https://colab.research.google.com/github/lancedb/vectordb-recipes/blob/main/tutorials/RAG-with_MatryoshkaEmbed-Llamaindex/RAG_with_MatryoshkaEmbedding_and_Llamaindex.ipynb#scrollTo=hgVHOEBZ2lS5

from llama_index.core import VectorStoreIndex, Settings, StorageContext
from llama_index.vector_stores.lancedb import LanceDBVectorStore
from llama_index.llms.openai import OpenAI
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
import lancedb

from data_utils import changes_detected
from setup import setup_cloud_resources, assume_limited_role






# initialize the LanceDBVectorStore
def init_vector_store(db_uri):
    # Initialize LanceDB with the temporary credentials
    try:
        db = lancedb.connect(
            db_uri,

            storage_options={
                "timeout": "60s",
                "aws_access_key_id": credentials['AccessKeyId'],
                "aws_secret_access_key": credentials['SecretAccessKey'],
                "aws_session_token": credentials['SessionToken'], }
        )
        print("Connected to LanceDB.")
    except Exception as e:
        print(f"Error connecting to LanceDB: {e}")
        raise

    db.table_names()
    # todo - below
    return db


def build_RAG(
        input_data_dir, matryoshka_embedding_model,
        matryoshka_embedding_size, db,
        table_name
):
    """
    This function sets embedding model, llm, and vector store to be used for creating RAG index.
    If changes are detected in the input data directory, the vector store is cleared and recreated.
    """

    # Set the embedding model
    Settings.embed_model = HuggingFaceEmbedding(
        model_name=matryoshka_embedding_model,
        truncate_dim=int(matryoshka_embedding_size),
    )

    # Set the language model
    Settings.llm = OpenAI()  # Uses API key from the environment

    # Check if a LanceDB connection is provided
    if db is None:
        raise ValueError("A valid LanceDB connection (`db`) must be provided.")

    # Initialize the LanceDBVectorStore
    vector_store = LanceDBVectorStore(uri=db_uri, table_name=table_name)

    # Initialize storage context
    storage_context = StorageContext.from_defaults(vector_store=vector_store)

    changes, documents = changes_detected(input_data_dir)
    # Check for changes in the input data directory
    if changes:  # changes_detected(input_data_dir):
        # If changes are detected, clear the vector store
        print("Changes detected in the input data. Clearing and recreating the vector store.")
        tables = db.table_names()
        if table_name in tables:
            table = db.open_table(table_name)
            table.delete("1=1")  # Clear the LanceDB table
        # Recreate the index from the documents
        index = VectorStoreIndex.from_documents(documents, storage_context=storage_context)
    else:
        # Use the existing vector store if no changes are detected
        print("Data already vectorized and stored in the database.")
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
    db_name = ""        # Database name
    bucket_name = ""
    project_id_prefix = ""   # Unique name for your project
    #   (also used for s3 bucket so no spaces or underscores)
    bucket_name = project_id_prefix + 'lancedb-on-s3'

    setup_cloud_resources(bucket_name)
    _, _, credentials = assume_limited_role()

    input_data_dir = "data"
    if not os.path.exists(input_data_dir):
        os.makedirs(input_data_dir)
    if os.path.exists(input_data_dir + "/document_1.pdf"):
        print("PDFs already downloaded.")
    else:
        print("Downloading PDFs...")
        # download_pdfs(pdf_urls)
    db_uri = f"s3://{bucket_name}/{db_name}/"
    matryoshka_embedding_model = "tomaarsen/mpnet-base-nli-matryoshka"
    matryoshka_embedding_size = 256

    db = init_vector_store(db_uri)

    query_engine = build_RAG(
        input_data_dir, matryoshka_embedding_model, matryoshka_embedding_size, db,
        table_name="gale-encyclopedia-of-medicine"
    )

    interactive_session()

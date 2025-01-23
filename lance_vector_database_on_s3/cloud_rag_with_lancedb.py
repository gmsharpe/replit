# pip install llama-index llama-index-embeddings-huggingface llama-index-readers-web llama-index-vector-stores-lancedb diffusers huggingface-hub -q
import hashlib
import json
import os
import pickle

# adopted from https://colab.research.google.com/github/lancedb/vectordb-recipes/blob/main/tutorials/RAG-with_MatryoshkaEmbed-Llamaindex/RAG_with_MatryoshkaEmbedding_and_Llamaindex.ipynb#scrollTo=hgVHOEBZ2lS5

from llama_index.core import VectorStoreIndex, Settings, StorageContext, SimpleDirectoryReader
from llama_index.vector_stores.lancedb import LanceDBVectorStore
from llama_index.llms.openai import OpenAI
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
import lancedb

from setup import credentials, bucket_name, db_name

import requests

# download the pdfs from the google drive file_ids
pdf_urls = [
    "0B7HZIUBvCH1EVGxpNEdXVklLQk0",
    "0B7HZIUBvCH1EaklDOFhPUHo0eTQ",
    "0B7HZIUBvCH1EVGxpNEdXVklLQk0",
    "0B7HZIUBvCH1EZ1REYVFnYjZscTQ"
]


def changes_detected(data_directory):
    doc_dir = os.path.join(input_data_dir, "documents.pkl")
    """Calculate a hash based on the contents of the directory."""
    hash_obj = hashlib.md5()
    for root, _, files in os.walk(data_directory):
        for file in sorted(files):  # Ensure consistent order
            # don't read the 'hash.json' file
            if file != 'hash.json' and file != 'documents.pkl':
                with open(os.path.join(root, file), 'rb') as f:
                    hash_obj.update(f.read())
    current_hash = hash_obj.hexdigest()

    # Check if hash file exists and compare hashes
    hash_path = os.path.join(data_directory, "hash.json")

    if os.path.exists(hash_path):
        with open(hash_path, 'r') as f:
            saved_hash = json.load(f).get('hash')
    else:
        # Save the new hash
        with open(hash_path, 'w') as f:
            json.dump({'hash': current_hash}, f)
        saved_hash = None

    if saved_hash == current_hash:
        print("No changes in the data directory. Skipping vectorization.")
        changes = False
        if os.path.exists(os.path.join(data_directory, "documents.pkl")):
            with open(doc_dir, "rb") as f:
                documents = pickle.load(f)
            return changes, documents
        else:
            # Load new documents from the input directory
            documents = SimpleDirectoryReader(input_data_dir, exclude=["hash.json", "documents.pkl"]).load_data()
            return changes, documents

    else:
        changes = True
        documents = SimpleDirectoryReader(input_data_dir).load_data()
        with open(doc_dir, "wb") as f:
            pickle.dump(documents, f)
        return changes, documents


# Function to download the PDF
# https://drive.usercontent.google.com/u/0/uc?id=0B7HZIUBvCH1EVGxpNEdXVklLQk0&export=download
def download_pdf(id, filename):
    response = requests.get(f"https://drive.usercontent.google.com/u/0/uc?id={id}&export=download", stream=True)
    if response.status_code == 200:
        with open(filename, "wb") as pdf_file:
            for chunk in response.iter_content(chunk_size=1024):
                pdf_file.write(chunk)
        print(f"Downloaded: {filename}")
    else:
        print(f"Failed to download: {filename} - Status Code: {response.status_code}")


def download_pdfs(ids):
    # Loop through the URLs and download each PDF
    for index, id in enumerate(ids):
        # Generate the filename
        filename = f"data/document_{index + 1}.pdf"
        # Download the PDF
        download_pdf(id, filename)


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

# test_lancedb_client.py

from client import LanceDBClient  # Replace 'your_module' with the actual module name
import lancedb

defaults = {
    "embedding_model": "snowflake-arctic-embed2",
    "catalog_table_name": "catalog",
    "chunks_table_name": "chunks",
    "summarization_model": "llama3.1:8b"
}


def test_lancedb_client():
    # Define the parameters
    database_url = "test_db"  # Replace with your actual database URL
    chunks_table_name = "chunks_table"
    catalog_table_name = "catalog_table"


    # Instantiate the LanceDBClient
    client = LanceDBClient(
        database_url=database_url,
        chunks_table_name=chunks_table_name,
        catalog_table_name=catalog_table_name,
        defaults=defaults
    )

    try:
        # Connect to the database
        client.connect()
        print("Connected to LanceDB successfully.")

        # Access the chunks vector store
        chunks_vector_store = client.get_chunks_vector_store()
        print("Chunks Vector Store:", chunks_vector_store)

        # Access the catalog vector store
        catalog_vector_store = client.get_catalog_vector_store()
        print("Catalog Vector Store:", catalog_vector_store)

        # Perform additional operations as needed
        # For example, you might want to insert data, query the vector stores, etc.

    except Exception as e:
        print("An error occurred during testing:", e)

    finally:
        # Close the connection
        client.close()
        print("Connection closed.")

if __name__ == "__main__":
    test_lancedb_client()

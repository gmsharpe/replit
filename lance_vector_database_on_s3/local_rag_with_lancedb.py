# pip install llama-index llama-index-embeddings-huggingface llama-index-readers-web llama-index-vector-stores-lancedb diffusers huggingface-hub -q

# adopted from https://colab.research.google.com/github/lancedb/vectordb-recipes/blob/main/tutorials/RAG-with_MatryoshkaEmbed-Llamaindex/RAG_with_MatryoshkaEmbedding_and_Llamaindex.ipynb#scrollTo=hgVHOEBZ2lS5

from llama_index.core import VectorStoreIndex, Settings, StorageContext
from llama_index.readers.web import SimpleWebPageReader
from llama_index.vector_stores.lancedb import LanceDBVectorStore
from llama_index.llms.openai import OpenAI
from llama_index.embeddings.huggingface import HuggingFaceEmbedding


def get_doc_from_url(url):
    """
    This function reads dataset from url and returns the documents.
    """
    documents = SimpleWebPageReader(html_to_text=True).load_data([url])
    return documents


def build_RAG(
        url, matryoshka_embedding_model, matryoshka_embedding_size, db_uri
):
    """
    This function sets embedding model, llm and vector store to be used for creating RAG index.
    """

    Settings.embed_model = HuggingFaceEmbedding(
        model_name=matryoshka_embedding_model,
        truncate_dim=int(matryoshka_embedding_size),
    )
    Settings.llm = OpenAI()  # This will now use the API key from the environment
    documents = get_doc_from_url(url)
    vector_store = LanceDBVectorStore(uri=db_uri)
    storage_context = StorageContext.from_defaults(vector_store=vector_store)
    index = VectorStoreIndex.from_documents(documents, storage_context=storage_context)
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
    db_uri = 'tmp/lancedb'
    source_url='https://en.wikipedia.org/wiki/Deadpool_(film)'
    matryoshka_embedding_model = "tomaarsen/mpnet-base-nli-matryoshka"
    matryoshka_embedding_size = 256
    query_engine = build_RAG(
        source_url, matryoshka_embedding_model, matryoshka_embedding_size, db_uri
    )

    interactive_session()

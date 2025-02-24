import lancedb
from lancedb.pydantic import LanceModel
from langchain_community.vectorstores import LanceDB
from langchain_ollama import OllamaEmbeddings

class Metadata(LanceModel):
    source: str
    hash: str

class CatalogRecord(LanceModel):
    page_content: int
    metadata: Metadata

class LanceDBClient:
    def __init__(self, database_url: str, chunks_table_name: str, catalog_table_name: str, defaults: dict[str, str]):
        self.database_url = database_url
        self.chunks_table_name = chunks_table_name
        self.catalog_table_name = catalog_table_name
        self.client = None
        self.chunks_table = None
        self.chunks_vector_store = None
        self.catalog_table = None
        self.catalog_vector_store = None
        self.defaults = defaults
        self.embedding_model = OllamaEmbeddings(model="snowflake-arctic-embed2")

    def connect(self):
        try:
            print(f"Connecting to database: {self.database_url}")
            self.client = lancedb.connect(self.database_url)

            # Initialize or create the chunks table
            if self.chunks_table_name in self.client.table_names():
                self.chunks_table = self.client.open_table(self.chunks_table_name)
            else:
                self.chunks_table = self.client.create_table(self.chunks_table_name, schema=LanceModel.to_arrow_schema())
            self.chunks_vector_store = LanceDB(
                uri=self.database_url,
                embedding=self.embedding_model,
                table_name=self.chunks_table.name,
            )

            # Initialize or create the catalog table
            if self.catalog_table_name in self.client.table_names():
                self.catalog_table = self.client.open_table(self.catalog_table_name)
            else:
                self.catalog_table = self.client.create_table(self.catalog_table_name, schema=LanceModel.to_arrow_schema())
            self.catalog_vector_store = LanceDB(
                uri=self.database_url,
                embedding=self.embedding_model,
                table_name=self.catalog_table.name,
            )
        except Exception as error:
            print("LanceDB connection error:", error)
            raise
        return self

    def disconnect(self):
        self.close()

    def close(self):
        if self.client:
            self.client.close()
            print("LanceDB connection closed.")

    def get_chunks_vector_store(self) -> LanceDB:
        return self.chunks_vector_store

    def get_catalog_vector_store(self) -> LanceDB:
        return self.catalog_vector_store

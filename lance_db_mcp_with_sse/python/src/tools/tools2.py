import json
from abc import ABC, abstractmethod
from abc import ABC, abstractmethod
from typing import Any, TypeVar, Generic, Type

from langchain_community.vectorstores import LanceDB
from litellm.types.llms.bedrock import ToolResultBlock, ToolResultContentBlock
# from llama_cloud import ImageBlock
from pydantic import BaseModel, Field


class McpError(Exception):
    class ErrorCode:
        INVALID_REQUEST = "InvalidRequest"

    def __init__(self, code: str, message: str):
        self.code = code
        super().__init__(message)


# https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ToolResultContentBlock.html
# https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ToolResultBlock.html



class ToolParams(BaseModel):
    text: str = Field(..., description="Search string")


T = TypeVar("T", bound=ToolParams)


class BaseTool(ABC, Generic[T]):
    @property
    @abstractmethod
    def name(self) -> str:
        pass

    @property
    @abstractmethod
    def description(self) -> str:
        pass

    @property
    @abstractmethod
    def input_schema(self) -> BaseModel:
        pass

    @abstractmethod
    def execute(self, params: T) -> ToolResultBlock:
        pass

    def validate_database(self, database: Any) -> str:
        if not isinstance(database, str):
            raise McpError(McpError.ErrorCode.INVALID_REQUEST, f"Database name must be a string, got {type(database).__name__}")
        return database

    def validate_collection(self, collection: Any) -> str:
        if not isinstance(collection, str):
            raise McpError(McpError.ErrorCode.INVALID_REQUEST, f"Collection name must be a string, got {type(collection).__name__}")
        return collection

    def handle_error(self, error: Any) -> ToolResultBlock:
        return ToolResultBlock(
            toolUseId="placeholder_toolUseId",
            content=[ToolResultContentBlock(text=str(error))],
            status="error"
        )


class BroadSearchParams(BaseModel):
    text: str


class BroadSearchTool(BaseTool[BroadSearchParams]):
    def __init__(self, vector_store: LanceDB):
        self.vector_store = vector_store

    @property
    def name(self) -> str:
        return "all_chunks_search"

    @property
    def description(self) -> str:
        return "Search for relevant document chunks in the vector store across all documents."

    @property
    def input_schema(self) -> Type[BroadSearchParams]:
        return BroadSearchParams

    def execute(self, params: BroadSearchParams) -> ToolResultBlock:
        try:
            retriever = self.vector_store.as_retriever()
            results = retriever.invoke(params.text)
            content = [ToolResultContentBlock(json={ "source": doc.metadata["source"], "text": doc.page_content }
                                              ) for doc in results]
            return ToolResultBlock(
                toolUseId="placeholder_toolUseId",
                content=content,
                status="success"
            )
        except Exception as error:
            return self.handle_error(error)


class CatalogSearchParams(BaseModel):
    text: str


class CatalogSearchTool(BaseTool[CatalogSearchParams]):
    def __init__(self, vector_store: LanceDB):
        self.vector_store = vector_store

    @property
    def name(self) -> str:
        return "catalog_search"

    @property
    def description(self) -> str:
        return "Search for relevant documents in the catalog"

    @property
    def input_schema(self) -> Type[CatalogSearchParams]:
        return CatalogSearchParams

    def execute(self, params: CatalogSearchParams) -> ToolResultBlock:
        try:
            retriever = self.vector_store.as_retriever()
            results = retriever.invoke(params.text)
            content = [ToolResultContentBlock(json={ "source": doc.metadata["source"], "text": doc.page_content }
                                              ) for doc in results]
            return ToolResultBlock(
                toolUseId="placeholder_toolUseId",
                content=content,
                status="success"
            )
        except Exception as error:
            return self.handle_error(error)


class ChunksSearchParams(BaseModel):
    text: str
    source: str


class ChunksSearchTool(BaseTool[ChunksSearchParams]):
    def __init__(self, vector_store: LanceDB):
        self.vector_store = vector_store

    @property
    def name(self) -> str:
        return "chunks_search"

    @property
    def description(self) -> str:
        return "Search for relevant document chunks in the vector store based on a source document."

    @property
    def input_schema(self) -> Type[ChunksSearchParams]:
        return ChunksSearchParams

    def execute(self, params: ChunksSearchParams) -> ToolResultBlock:
        try:
            retriever = self.vector_store.as_retriever()
            results = retriever.invoke(params.text)

            print("Filtering out all results not from source", params.source)

            # Filter results by source if provided
            filtered_results = [doc for doc in results if doc.metadata["source"].replace('\\\\', '\\') == params.source.replace('\\\\', '\\')]

            content = [ToolResultContentBlock(json={ "source": doc.metadata["source"], "text": doc.page_content }
                                              ) for doc in filtered_results]
            return ToolResultBlock(
                toolUseId="placeholder_toolUseId",
                content=content,
                status="success"
            )
        except Exception as error:
            return self.handle_error(error)

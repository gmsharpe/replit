import logging
from typing import List, Optional

from langchain_community.vectorstores import LanceDB
from litellm.types.llms.bedrock import ToolResultBlock, ToolResultContentBlock

logger = logging.getLogger(__name__)

DEFAULT_TOOL_USE_ID = "default_tool_use_id"

def perform_retrieval(vector_store: LanceDB, text: str, source_filter: Optional[str] = None, k: Optional[int] = None) -> List[ToolResultContentBlock]:
    retriever = vector_store.as_retriever(search_kwargs={"k": k} if k else {})
    results = retriever.invoke(text)

    if source_filter:
        normalized_filter = source_filter.replace('\\\\', '\\')
        results = [
            doc for doc in results
            if doc.metadata["source"].replace('\\\\', '\\') == normalized_filter
        ]

    return [
        ToolResultContentBlock(json={"source": doc.metadata["source"], "text": doc.page_content})
        for doc in results
    ]

def execute_search_tool(
        vector_store: LanceDB,
        text: str,
        source_filter: Optional[str] = None,
        tool_use_id: str = DEFAULT_TOOL_USE_ID,
        k: Optional[int] = None
) -> ToolResultBlock:
    try:
        content = perform_retrieval(vector_store, text, source_filter, k)
        return ToolResultBlock(
            toolUseId=tool_use_id,
            content=content,
            status="success"
        )
    except Exception as error:
        logger.exception("Search tool error")
        return ToolResultBlock(
            toolUseId=tool_use_id,
            content=[ToolResultContentBlock(text="An internal error occurred during search.")],
            status="error"
        )

# Wrappers for backward compatibility
def broad_search_tool(vector_store: LanceDB, text: str) -> ToolResultBlock:
    return execute_search_tool(vector_store, text)

def catalog_search_tool(vector_store: LanceDB, text: str) -> ToolResultBlock:
    return execute_search_tool(vector_store, text)

def chunk_search_tool(vector_store: LanceDB, text: str, source: str) -> ToolResultBlock:
    return execute_search_tool(vector_store, text, source_filter=source)

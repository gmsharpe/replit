import json
import logging
import os
import sys
from dataclasses import dataclass
from typing import Dict, Optional

import anyio
from langchain_community.vectorstores import LanceDB
from mcp.server.fastmcp import FastMCP

from config import defaults
from lance_db_mcp_with_sse.python.src.lancedb.client import LanceDBClient
from lance_db_mcp_with_sse.python.src.tools.tools import (
    broad_search_tool,
    catalog_search_tool,
    chunk_search_tool,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

"""
MCP Server Initialization: The FastMCP class from the mcp.server.fastmcp module initializes the MCP server with specified capabilities.

pip install git+https://github.com/modelcontextprotocol/python-sdk/archive/refs/tags/v1.3.0rc1.zip

"""
@dataclass
class LanceDBConfig:
    db_uri: str
    params: Dict[str, str]
    chunks_table: str = "chunks"
    catalog_table: str = "catalog"

class LanceDBFastMCP:
    def __init__(self, config: LanceDBConfig):
        self.config = config
        self.mcp = FastMCP("lancedb-mcp")

        self.db_uri = self.resolve_db_uri(config.db_uri)
        self.db_client = LanceDBClient(
            self.db_uri,
            config.chunks_table,
            config.catalog_table,
            config.params,
        )
        self.chunks_vector_store: Optional[LanceDB] = None
        self.catalog_vector_store: Optional[LanceDB] = None

        self.setup_database()
        self.register_tools()

    @staticmethod
    def resolve_db_uri(db_uri: str) -> str:
        return os.path.abspath(db_uri)

    def setup_database(self) -> None:
        try:
            self.db_client.connect()
            self.chunks_vector_store = self.db_client.get_chunks_vector_store()
            self.catalog_vector_store = self.db_client.get_catalog_vector_store()
            logger.info(f"Connected to LanceDB at {self.db_uri}")
        except Exception as error:
            logger.exception("Failed to connect to LanceDB")
            sys.exit(1)

    def register_tools(self) -> None:
        @self.mcp.tool(description="Search document chunks across all documents.")
        def broad_search(text: str) -> str:
            tool_response = broad_search_tool(self.chunks_vector_store, text)
            return json.dumps(tool_response)

        @self.mcp.tool(description="Search documents in the catalog.")
        def catalog_search(text: str) -> str:
            tool_response = catalog_search_tool(self.catalog_vector_store, text)
            return json.dumps(tool_response)

        @self.mcp.tool(description="Search chunks from a specific catalog source.")
        def chunk_search(text: str, source: str) -> str:
            tool_response = chunk_search_tool(self.chunks_vector_store, text, source)
            return json.dumps(tool_response)

    async def run_server(self) -> None:
        try:
            logger.info("Starting LanceDB MCP server...")
            await self.mcp.run_sse_async()
            logger.info("LanceDB MCP server running with SSE.")
        except Exception as error:
            logger.exception("Failed to start MCP server. Error: " + str(error))
            sys.exit(1)

def main():
    config = LanceDBConfig(
        db_uri=os.getenv("LANCEDB_URI", "lancedb/test_db"),
        params=defaults,
    )
    server = LanceDBFastMCP(config)
    anyio.run(server.run_server)

if __name__ == "__main__":
    main()

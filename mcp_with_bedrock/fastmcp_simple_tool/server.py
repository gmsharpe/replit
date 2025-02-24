from mcp.server.fastmcp import FastMCP


class LanceDBFastMCP:
    def __init__(self, database_url: str):
        self.database_url = database_url
        self.lancedb_client = None
        self.mcp = FastMCP("lancedb-mcp")
        self.init_mcp(self.mcp)

    def init_mcp(self, mcp: FastMCP):
        # Add an addition tool
        @mcp.tool()
        def add(a: int, b: int) -> int:
            """Add two numbers"""
            return a + b


        # Add a dynamic greeting resource
        @mcp.resource("greeting://{name}")
        def get_greeting(name: str) -> str:
            """Get a personalized greeting"""
            return f"Hello, {name}!"

        self.mcp.run(transport="sse")



if __name__ == "__main__":
    db_url = ""
    server = LanceDBFastMCP(db_url)
    server.mcp.run_sse_async()
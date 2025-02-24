import asyncio
import json
import boto3
import logging
import os
from contextlib import asynccontextmanager
from typing import Dict, Any

from mcp.client.session import ClientSession
from mcp.client.sse import sse_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants (ideally configurable through environment or config file)
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "anthropic.claude-3-5-haiku-20241022-v1:0")
BEDROCK_MAX_TOKENS = 4000
BEDROCK_TOP_P = 0.1
BEDROCK_TEMPERATURE = 0
SSE_URL = os.getenv("SSE_URL", "http://localhost:8000/sse")


def flatten_schema(schema: Dict[str, Any]) -> Dict[str, Any]:
    """
    Replaces $ref with the corresponding definition from $defs and removes $defs.
    :param schema:
    :return:
    """
    definitions = schema.pop("$defs", {})

    def resolve_ref(ref: str) -> Dict[str, Any]:
        ref_key = ref.split("/")[-1]
        return definitions.get(ref_key, {})

    for key, value in schema["properties"].items():
        if isinstance(value, dict) and "$ref" in value:
            schema["properties"][key] = resolve_ref(value["$ref"])

    return schema


def convert_tool_format(tools) -> Dict[str, Any]:
    """
    Converts tools into the format required for the Bedrock API.
    :param tools:
    :return:
    """
    if not isinstance(tools, list):
        tools = [tools]

    return {
        "tools": [
            {
                "toolSpec": {
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": {"json": flatten_schema(tool.inputSchema)},
                }
            }
            for tool in tools
        ]
    }


@asynccontextmanager
async def initialize_session(url: str):
    async with sse_client(url) as streams:
        session = ClientSession(streams[0], streams[1])
        try:
            await session.initialize()
            await asyncio.sleep(1)  # Ensure proper initialization
            yield session
        except Exception as e:
            logger.exception("Error initializing session: %s", e)
            raise


async def get_tools(session: ClientSession) -> Dict[str, Any]:
    """
    Fetches and formats tools from the MCP.
    :param session:
    :return:
    """
    tools_result = await session.list_tools()
    tools_formatted = convert_tool_format(tools_result.tools)
    logger.info("Tools fetched and formatted: %s", tools_formatted)
    return tools_formatted


async def call_bedrock_model(bedrock, messages, system, tools_list):
    response = bedrock.converse(
        modelId=BEDROCK_MODEL_ID,
        messages=messages,
        system=[system],
        inferenceConfig={
            "maxTokens": BEDROCK_MAX_TOKENS,
            "topP": BEDROCK_TOP_P,
            "temperature": BEDROCK_TEMPERATURE,
        },
        toolConfig=tools_list,
    )
    return response


async def handle_tool_requests(session, tool_requests, messages):
    for tool_request in tool_requests:
        if "toolUse" in tool_request:
            tool = tool_request["toolUse"]
            logger.info("Executing tool: %s with request ID: %s", tool["name"], tool["toolUseId"])

            try:
                tool_response = await session.call_tool(tool["name"], tool["input"])
                content_text = tool_response.content[0].text.replace("default_tool_use_id", tool["toolUseId"])
                tool_result = json.loads(content_text)
                logger.info("Tool executed successfully: %s", tool_result)
            except Exception as err:
                logger.exception("Tool execution error")
                tool_result = {
                    "toolUseId": tool["toolUseId"],
                    "content": [{"text": f"Error: {str(err)}"}],
                    "status": "error",
                }

            messages.append({"role": "user", "content": [{"toolResult": tool_result}]})


async def main():
    bedrock = boto3.client("bedrock-runtime")

    system_prompt = {
        "text": """
You are a helpful AI assistant with access to the following tools:

1. `catalog_search`: First, use this tool to find documents relevant to the user's query.
2. `chunk_search`: If `catalog_search` returns relevant results, next use this tool with the specific source document to refine your search.
3. `broad_search`: If `catalog_search` returns no relevant results, use this tool to conduct a more general search across all available documents.

Always follow the order above and clearly explain the results to the user. Do not call `broad_search` if `catalog_search` and `chunk_search` return relevant results.
"""
    }

    messages = [{"role": "user", "content": [{"text": "Why is the health care system so broken?"}]}]

    async with initialize_session(SSE_URL) as session:
        tools_list = await get_tools(session)

        while True:
            response = await call_bedrock_model(bedrock, messages, system_prompt, tools_list)
            output_message = response["output"]["message"]
            messages.append(output_message)
            stop_reason = response["stopReason"]

            for content in output_message["content"]:
                if "text" in content:
                    logger.info("Model response: %s", content["text"])

            if stop_reason == "tool_use":
                await handle_tool_requests(session, output_message["content"], messages)
            else:
                logger.info("Interaction complete.")
                break


if __name__ == "__main__":
    asyncio.run(main())

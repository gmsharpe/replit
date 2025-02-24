import asyncio
import json

import boto3
import logging
from mcp.client.session import ClientSession
from mcp.client.sse import sse_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Function to flatten JSON Schema
def flatten_schema(schema):
    """Replaces $ref with the corresponding definition from $defs and removes $defs."""
    if "$defs" in schema:
        definitions = schema.pop("$defs")  # Extract definitions
    else:
        definitions = {}

    def resolve_ref(ref):
        """Resolves a $ref key."""
        ref_key = ref.split("/")[-1]  # Extract the reference key
        return definitions.get(ref_key, {})

    # Process properties and inline references
    properties = schema["properties"]
    for key, value in properties.items():
        if isinstance(value, dict) and "$ref" in value:
            properties[key] = resolve_ref(value["$ref"])  # Replace $ref with actual definition

    return schema


def convert_tool_format(tools):
    """
    Converts tools into the format required for the Bedrock API.

    https://docs.aws.amazon.com/bedrock/latest/userguide/tool-use.html

    Args:
        tools (list): List of tool objects

    Returns:
        dict: Tools in the format required by Bedrock
    """
    converted_tools = []
    tools = tools if isinstance(tools, list) else [tools]


    for tool in tools:

        tool_schema = flatten_schema(tool.inputSchema)

        converted_tool = {
            "toolSpec": {
                "name": tool.name,
                "description": tool.description,
                "inputSchema": {
                    "json": tool_schema
                }
            }
        }
        converted_tools.append(converted_tool)

    return {"tools": converted_tools}


async def main():
    # Initialize Bedrock client
    bedrock = boto3.client('bedrock-runtime')

    async with sse_client("http://localhost:8000/sse") as streams:
        async with ClientSession(streams[0], streams[1]) as session:
            await session.initialize()
            # sleep a bit to allow the session to be initialized
            await asyncio.sleep(1)

            # List available tools and convert to serializable format
            tools_result = await session.list_tools()
            tools_list = convert_tool_format(tools_result.tools)
            logger.info("Available tools: %s", tools_list)


            # Prepare the request for Nova Pro model
            system = [
                {
                        "text": """
You are a helpful AI assistant with access to the following tools:

1. `catalog_search`: First, use this tool to find documents relevant to the user's query.
2. `chunk_search`:   If `catalog_search` returns relevant results, next use this tool with the specific source document 
                     to refine your search.
3. `broad_search`:   If `catalog_search` returns no relevant results, use this tool to conduct a more general search 
                     across all available documents.

Always follow the order above and clearly explain the results to the user. Do not call `broad_search` if `catalog_search` 
and `chunk_search` return relevant results.
"""
                }
            ]

            messages = [
                {
                    "role": "user",
                    "content": [{"text": "Why is the health care system so broken?"}]
                }
            ]

            while True:
                # Call Bedrock with Nova Pro model
                response = bedrock.converse(
                    modelId='anthropic.claude-3-5-haiku-20241022-v1:0', #'us.amazon.nova-pro-v1:0',
                    messages=messages,
                    system=system,
                    inferenceConfig={
                        "maxTokens": 4000,
                        "topP": 0.1,
                        "temperature": 0
                    },
                    toolConfig=tools_list
                )

                output_message = response['output']['message']
                messages.append(output_message)
                stop_reason = response['stopReason']

                # Print the model's response
                for content in output_message['content']:
                    if 'text' in content:
                        print("Model:", content['text'])

                if stop_reason == 'tool_use':
                    # Tool use requested. Call the tool and send the result to the model.
                    tool_requests = response['output']['message']['content']
                    print(tool_requests)
                    for tool_request in tool_requests:
                        if 'toolUse' in tool_request:
                            tool = tool_request['toolUse']
                            logger.info("Requesting tool %s. Request: %s",
                                        tool['name'], tool['toolUseId'])

                            try:
                                # Call the tool through the MCP session
                                tool_response = await session.call_tool(tool['name'], tool['input'])
                                tool_result = json.loads(tool_response.content[0].text.replace("default_tool_use_id", tool['toolUseId']))
                                print(tool_result)

                            except Exception as err:
                                logger.error("Tool call failed: %s", str(err))
                                tool_result = {
                                    "toolUseId": tool['toolUseId'],
                                    "content": [{"text": f"Error: {str(err)}"}],
                                    "status": "error"
                                }

                            # Add tool result to messages
                            messages.append({
                                "role": "user",
                                "content": [{"toolResult": tool_result}]
                            })
                else:
                    # No more tool use requests, we're done
                    break

if __name__ == "__main__":
    asyncio.run(main())
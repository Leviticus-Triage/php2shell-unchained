#!/usr/bin/env python3
"""Parity client: calls the CURRENT mcp/php2shell_lab_mcp.py over stdio (MCP protocol).

Usage: python3 mcp/mcp_parity_client.py <tool> [json_args]
Prints the tool result text to stdout. Used by the validation run to prove the
current server code works (the long-running Cursor MCP instance needs a reload
to pick up code changes).
"""
from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

SERVER = Path(__file__).resolve().parent / "php2shell_lab_mcp.py"


async def call(tool: str, args: dict) -> str:
    params = StdioServerParameters(command=sys.executable, args=[str(SERVER)])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            names = [t.name for t in tools.tools]
            if tool == "__list__":
                return "\n".join(names)
            result = await session.call_tool(tool, args)
            parts = []
            for c in result.content:
                parts.append(getattr(c, "text", str(c)))
            return "\n".join(parts)


def main() -> None:
    tool = sys.argv[1] if len(sys.argv) > 1 else "__list__"
    args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    out = asyncio.run(call(tool, args))
    print(out[:4000])


if __name__ == "__main__":
    main()

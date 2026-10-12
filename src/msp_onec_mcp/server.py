"""STDIO MCP for diagnostics. No writes, shell access or arbitrary URL requests."""

from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from .cli import safe_probe
from .config import config_presence

mcp = FastMCP("MSP 1C Diagnostic", instructions="Read-only 1C OData metadata diagnostics")


@mcp.tool()
def onec_connection_configured() -> dict:
    """Check only whether 1C connection variables exist; reveal no credentials."""
    return {"configuration": config_presence()}


@mcp.tool()
def onec_metadata_overview(limit: int = 50) -> dict:
    """Read a bounded structural summary of 1C OData $metadata (never writes)."""
    return safe_probe(limit=limit)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()

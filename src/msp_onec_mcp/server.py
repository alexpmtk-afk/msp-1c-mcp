"""STDIO MCP for read-only diagnostics and opt-in selected 1C stock."""

from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from .cli import safe_probe
from .config import config_presence
from .selected_stock import selected_stock

mcp = FastMCP("MSP 1C Diagnostic", instructions="Read-only 1C OData metadata diagnostics")


@mcp.tool()
def onec_connection_configured() -> dict:
    """Check only whether 1C connection variables exist; reveal no credentials."""
    return {"configuration": config_presence()}


@mcp.tool()
def onec_metadata_overview(limit: int = 50) -> dict:
    """Read a bounded structural summary of 1C OData $metadata (never writes)."""
    return safe_probe(limit=limit)


@mcp.tool()
def onec_stock_by_guid(item_guid: str, warehouse_guid: str) -> dict:
    """Read test NewBase stock for one exact item and warehouse GUID (no writes).

    Identifiers must be canonical lowercase GUIDs. This tool is explicitly
    opt-in and uses the local VPS allowlisted queue, not a direct OData URL.
    """
    return selected_stock(item_guid, warehouse_guid)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()

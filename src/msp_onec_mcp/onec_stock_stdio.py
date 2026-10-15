#!/usr/bin/env python3
"""Isolated STDIO MCP endpoint: selected stock in test 1C NewBase, read-only.

Uses the existing allowlisted VPS loopback queue; no direct 1C connection.
JSON-RPC messages use one JSON object per line. No logs on stdout.
"""
from __future__ import annotations

import json
import sys

try:
    from .selected_stock import selected_stock
except ImportError:  # installed as two pinned files without other dependencies
    from selected_stock import selected_stock

try:
    from .natural_stock_vps import natural_stock
except ImportError:
    from natural_stock_vps import natural_stock

NATURAL_TOOL = {
    "name": "onec_stock_by_name_or_article",
    "description": (
        "Read the TEST 1C NewBase stock for ALL catalog items matching an exact "
        "human product name (Description) or business article (Артикул). "
        "Return every matching card (1, 2, 10, ...), with its own warehouses "
        "and balances, not a single guessed card. 1C Code (НФ-...) is "
        "display-only and MUST NEVER be a search input. Missing Balance rows "
        "are shown as zero with NO_BALANCE_ROW qualifier. Read-only."
    ),
    "annotations": {
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
    "inputSchema": {
        "type": "object",
        "properties": {
            "kind": {"type": "string", "enum": ["name", "article"]},
            "query": {"type": "string", "description": "Exact product name or business article, not 1C Code"},
            "warehouse_name": {"type": "string", "description": "Optional real warehouse title, omit for all"},
        },
        "required": ["kind", "query"],
        "additionalProperties": False,
    },
}

TOOL = {
    "name": "onec_stock_by_guid",
    "description": (
        "Read-only test 1C NewBase Balance quantity for an exact item and "
        "warehouse GUID. Does not change inventory or production data."
    ),
    "annotations": {
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
    "inputSchema": {
        "type": "object",
        "properties": {
            "item_guid": {"type": "string", "description": "Lowercase canonical 1C item UUID"},
            "warehouse_guid": {"type": "string", "description": "Lowercase canonical warehouse UUID"},
        },
        "required": ["item_guid", "warehouse_guid"],
        "additionalProperties": False,
    },
}


def tool_call(params: object) -> dict:
    if not isinstance(params, dict):
        raise ValueError("Invalid 1C MCP tool call")
    args = params.get("arguments")
    if not isinstance(args, dict):
        raise ValueError("Invalid 1C MCP arguments")
    if params.get("name") == TOOL["name"]:
        if set(args) != {"item_guid", "warehouse_guid"}:
            raise ValueError("Two GUID inputs are required; extra parameters forbidden")
        result = selected_stock(args["item_guid"], args["warehouse_guid"])
    elif params.get("name") == NATURAL_TOOL["name"]:
        if not {"kind", "query"} <= set(args) or set(args) - {"kind", "query", "warehouse_name"}:
            raise ValueError("Only name/article and optional warehouse name allowed")
        if args["kind"] not in ("name", "article"):
            raise ValueError("Internal 1C Code is not a query mode")
        result = natural_stock(args["kind"], args["query"], args.get("warehouse_name"))
    else:
        raise ValueError("Unknown 1C MCP tool")
    return {
        "content": [
            {"type": "text", "text": json.dumps(result, ensure_ascii=True, separators=(",", ":"))}
        ],
        "isError": result.get("status") not in ("PASS", "ITEM_NOT_FOUND"),
    }


def dispatch(message: dict) -> dict | None:
    request_id = message.get("id")
    method = message.get("method")
    if method == "notifications/initialized" or method == "notifications/cancelled":
        return None
    if "id" not in message:
        return None
    try:
        if method == "initialize":
            result = {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "onec-stock-newbase", "version": "0.1.0"},
            }
        elif method == "ping":
            result = {}
        elif method == "tools/list":
            result = {"tools": [TOOL, NATURAL_TOOL]}
        elif method == "tools/call":
            result = tool_call(message.get("params"))
        else:
            return {"jsonrpc": "2.0", "id": request_id,
                    "error": {"code": -32601, "message": "Method not found"}}
        return {"jsonrpc": "2.0", "id": request_id, "result": result}
    except (TypeError, ValueError):
        if method == "tools/call":
            return {"jsonrpc": "2.0", "id": request_id,
                    "result": {"isError": True, "content": [{"type": "text",
                               "text": '{"status":"INVALID_ARGUMENTS"}'}]}}
        return {"jsonrpc": "2.0", "id": request_id,
                "error": {"code": -32602, "message": "Invalid parameters"}}
    except Exception:
        return {"jsonrpc": "2.0", "id": request_id,
                "error": {"code": -32603, "message": "Internal server error"}}


def main() -> None:
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
                continue
            response = dispatch(message)
            if response is not None:
                sys.stdout.write(json.dumps(response, ensure_ascii=True, separators=(",", ":")) + "\n")
                sys.stdout.flush()
        except (ValueError, TypeError):
            continue


if __name__ == "__main__":
    main()

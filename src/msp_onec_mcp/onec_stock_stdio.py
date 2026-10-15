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

TOOL = {
    "name": "onec_stock_by_guid",
    "description": (
        "Read-only test 1C NewBase Balance quantity for an exact item and "
        "warehouse GUID. Does not change inventory or production data."
    ),
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
    if not isinstance(params, dict) or params.get("name") != TOOL["name"]:
        raise ValueError("Unknown 1C MCP tool")
    args = params.get("arguments")
    if not isinstance(args, dict) or set(args) != {"item_guid", "warehouse_guid"}:
        raise ValueError("Two GUID inputs are required; extra parameters forbidden")
    result = selected_stock(args["item_guid"], args["warehouse_guid"])
    return {
        "content": [
            {"type": "text", "text": json.dumps(result, ensure_ascii=True, separators=(",", ":"))}
        ],
        "isError": result.get("status") != "PASS",
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
            result = {"tools": [TOOL]}
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

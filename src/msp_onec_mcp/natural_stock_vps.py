"""Opt-in read-only multi-card stock from test NewBase through fixed VPS queue.

The relay protocol is ASCII-safe, but all user inputs are strictly validated
Cyrillic/Unicode by natural_stock_contract. No user-supplied URL, command,
GUID, SQL, Python execution or production 1C access.
"""
from __future__ import annotations

import json
import os
import re
import time
from urllib.request import Request, urlopen

try:
    from .natural_stock_contract import encode_lookup
except ImportError:  # VPS pinned file installation
    from natural_stock_contract import encode_lookup

AUTH = re.compile(r"[A-Za-z0-9_-]{32,128}\Z")
JOB = re.compile(r"ENQUEUED\|([0-9a-f]{32})\Z")
MAX_RESULT_BYTES = 262144
RESULT_STATES = {"PASS", "ITEM_NOT_FOUND", "ITEM_RESULT_INCOMPLETE",
                 "WAREHOUSE_NOT_FOUND", "WAREHOUSE_AMBIGUOUS",
                 "WAREHOUSE_RESULT_INCOMPLETE", "BALANCE_RESULT_INCOMPLETE",
                 "UNAVAILABLE"}


def natural_stock(kind: str, item_text: str, warehouse_name: str | None = None) -> dict:
    wire = encode_lookup(kind, item_text, warehouse_name)
    if os.environ.get("ONEC_ENABLE_NATURAL_STOCK") != "1":
        return {"status": "DISABLED", "reason": "Natural 1C stock tool not installed/enabled"}
    token = os.environ.get("ONEC_OPERATOR_TOKEN", "")
    port = os.environ.get("ONEC_RELAY_PORT", "9786")
    if not AUTH.fullmatch(token) or not port.isascii() or not port.isdecimal() or not 1 <= int(port) <= 65535:
        return {"status": "UNCONFIGURED"}
    prefix = "http://127.0.0.1:" + port
    headers = {"Authorization": "Bearer " + token, "Content-Type": "text/plain"}

    def request(path: str, *, body: bytes | None = None, limit=256) -> bytes:
        req = Request(prefix + path, data=body, method="POST" if body is not None else "GET",
                      headers=headers)
        try:
            with urlopen(req, timeout=8) as response:
                raw = response.read(limit + 1)
                if len(raw) > limit or response.status not in (200, 201):
                    raise RuntimeError("Unexpected reply")
                return raw
        except Exception:
            raise RuntimeError("Local 1C relay unavailable") from None

    try:
        created = request("/v1/admin/enqueue-natural", body=wire.encode("ascii")).decode("ascii").strip()
        match = JOB.fullmatch(created)
        if not match:
            return {"status": "ERROR", "reason": "Invalid enqueue acknowledgement"}
        job = match[1]
        for _ in range(24):
            time.sleep(5)
            status = request("/v1/admin/status/" + job).decode("ascii").strip()
            if not status.startswith("STATUS|" + job + "|"):
                return {"status": "ERROR", "reason": "Unrelated job status"}
            if "|done|" not in status:
                continue
            if status != "STATUS|" + job + "|done|NATURAL_RESULT":
                return {"status": "ERROR", "reason": "Wrong completed operation"}
            raw = request("/v1/admin/natural-result/" + job, limit=MAX_RESULT_BYTES)
            try:
                data = json.loads(raw.decode("utf-8"))
                if not isinstance(data, dict) or data.get("status") not in RESULT_STATES:
                    raise ValueError("Invalid result")
                if data["status"] != "PASS":
                    if set(data) != {"status"}:
                        raise ValueError("Unexpected failure response")
                    return data
                if data.get("search_kind") != kind or data.get("search_term") != item_text:
                    raise ValueError("Wrong search result")
                if data.get("requested_warehouse") != warehouse_name:
                    raise ValueError("Wrong warehouse result")
                matches = data.get("items")
                if (not isinstance(matches, list) or
                    not 1 <= len(matches) <= 50 or
                    data.get("match_count") != len(matches)):
                    raise ValueError("Wrong card count")
                # No internal reference is an output field. Server already
                # validates every field/quantity, but reject hidden GUID leaks.
                if re.search(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", raw.decode("utf-8"), re.I):
                    raise ValueError("Internal identifier exposed")
                return data
            except (ValueError, UnicodeError, TypeError):
                return {"status": "ERROR", "reason": "Rejected unsafe or mismatched 1C result"}
        return {"status": "PENDING", "reason": "No completed response within the bounded polling window"}
    except RuntimeError:
        return {"status": "ERROR", "reason": "Local 1C relay unavailable"}

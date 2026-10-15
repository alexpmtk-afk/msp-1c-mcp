"""Read-only 1C NewBase stock by two GUIDs through the local VPS job relay.

No direct 1C endpoint, URLs from caller, arbitrary operations, secrets in results,
or access to production. Requires explicit opt-in on the private VPS.
"""
from __future__ import annotations

import os
import re
import time
from urllib.request import Request, urlopen

GUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\Z")
JOB = re.compile(r"ENQUEUED\|([0-9a-f]{32})\Z")
QTY = r"-?[0-9]{1,9}(?:\.[0-9]{1,3})?"
NIL = "00000000-0000-0000-0000-000000000000"
AUTH = re.compile(r"[A-Za-z0-9_-]{32,128}\Z")


def validate_guid(value: str) -> str:
    if not isinstance(value, str) or not GUID.fullmatch(value) or value == NIL:
        raise ValueError("Expected a canonical, lowercase, nonzero 1C reference GUID")
    return value


def selected_stock(item_guid: str, warehouse_guid: str) -> dict:
    """Query only test 1C NewBase via operator-authorized loopback relay."""
    item = validate_guid(item_guid)
    warehouse = validate_guid(warehouse_guid)
    if os.getenv("ONEC_ENABLE_STOCK_SELECTED") != "1":
        return {"status": "DISABLED", "reason": "Selected stock MCP tool not enabled on VPS"}
    token = os.getenv("ONEC_OPERATOR_TOKEN", "")
    if not AUTH.fullmatch(token):
        return {"status": "UNCONFIGURED", "reason": "Local 1C operator credentials are unavailable"}
    port = os.getenv("ONEC_RELAY_PORT", "9786")
    if not port.isascii() or not port.isdecimal() or not 1 <= int(port) <= 65535:
        return {"status": "UNCONFIGURED", "reason": "Local 1C relay port is invalid"}
    root = "http://127.0.0.1:" + port
    headers = {"Authorization": "Bearer " + token, "Content-Type": "text/plain"}

    def relay(path: str, *, body: bytes | None = None) -> str:
        req = Request(root + path, data=body, method="POST" if body is not None else "GET", headers=headers)
        try:
            with urlopen(req, timeout=8) as response:
                raw = response.read(257)
                if response.status not in (200, 201) or len(raw) > 256:
                    raise RuntimeError("Unexpected 1C relay reply")
                return raw.decode("ascii").strip()
        except Exception:
            raise RuntimeError("1C relay unavailable") from None

    try:
        created = relay("/v1/admin/enqueue-selected", body=("STOCK|" + item + "|" + warehouse).encode("ascii"))
        match = JOB.fullmatch(created)
        if not match:
            return {"status": "ERROR", "reason": "Unexpected queue acknowledgement"}
        job_id = match[1]
        for _ in range(24):
            time.sleep(5)
            status = relay("/v1/admin/status/" + job_id)
            if not status.startswith("STATUS|" + job_id + "|"):
                return {"status": "ERROR", "reason": "Mismatched queue status"}
            if "|done|" not in status:
                continue
            success = re.fullmatch(
                r"STATUS\|" + job_id + r"\|done\|RESULT\|" + job_id
                + r"\|[0-9a-f]{32}\|PASS\|SELECTED_Q_(" + QTY + r")", status
            )
            if success:
                return {"status": "PASS", "quantity": success[1], "source": "1C NewBase Balance", "mode": "read-only"}
            failure = re.fullmatch(
                r"STATUS\|" + job_id + r"\|done\|RESULT\|" + job_id
                + r"\|[0-9a-f]{32}\|FAIL\|(ODATA_SELECTED_[A-Z_]+)", status
            )
            return {"status": "FAIL", "error_code": failure[1] if failure else "UNEXPECTED_RESULT"}
        return {"status": "PENDING", "reason": "No completed answer within the bounded polling window"}
    except RuntimeError:
        return {"status": "ERROR", "reason": "1C relay unavailable"}

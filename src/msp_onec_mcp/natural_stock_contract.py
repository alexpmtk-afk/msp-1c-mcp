"""Validated plain-language stock lookup request contract (offline, not deployed).

Only a future **fixed** NewBase read-only relay endpoint may accept this
protocol; no dynamic URLs, OData query fragments or SQL can enter the request.
UTF-8 values are base64url encoded for the legacy ASCII/TLS poll transport.
"""
from __future__ import annotations

import base64
import re
import unicodedata

PREFIX = "LOOKUP1"
B64 = re.compile(r"[A-Za-z0-9_-]+\Z")
KINDS = frozenset({"article", "name"})
MAX_WIRE = 1024


def validate_term(value: str, *, max_length: int, label: str) -> str:
    """Do not rewrite punctuation, case or whitespace inside 1C field values."""
    if not isinstance(value, str) or value != value.strip():
        raise ValueError(label + ": must be a nonempty trimmed string")
    if not 1 <= len(value) <= max_length:
        raise ValueError(label + ": length outside limits")
    if unicodedata.normalize("NFC", value) != value:
        raise ValueError(label + ": requires canonical Unicode NFC")
    for character in value:
        category = unicodedata.category(character)
        if category in {"Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"}:
            raise ValueError(label + ": contains control/invisible characters")
    return value


def _encode(value: str) -> str:
    return base64.urlsafe_b64encode(value.encode("utf-8")).rstrip(b"=").decode("ascii")


def _decode(value: str) -> str:
    if not value or not B64.fullmatch(value):
        raise ValueError("invalid base64url field")
    data = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    if _encode(data.decode("utf-8")) != value:
        raise ValueError("non-canonical encoded field")
    return data.decode("utf-8")


def encode_lookup(kind: str, item_text: str, warehouse_name: str | None = None) -> str:
    """Article/name and optional *human* warehouse name; missing means all warehouses."""
    if kind not in KINDS:
        raise ValueError("Unsupported lookup kind")
    item = validate_term(item_text, max_length=160 if kind == "name" else 96, label="item")
    warehouse = ("-" if warehouse_name is None else
                 _encode(validate_term(warehouse_name, max_length=100, label="warehouse")))
    message = "|".join((PREFIX, kind, _encode(item), warehouse))
    if len(message) > MAX_WIRE:
        raise ValueError("Encoded query too long")
    return message


def decode_lookup(message: str) -> dict[str, str | None]:
    """Strictly decode the same fixed operation, never an arbitrary OData request."""
    if not isinstance(message, str) or len(message) > MAX_WIRE:
        raise ValueError("Invalid message length")
    fields = message.split("|")
    if len(fields) != 4 or fields[0] != PREFIX or fields[1] not in KINDS:
        raise ValueError("Unsupported wire request")
    warehouse = None if fields[3] == "-" else _decode(fields[3])
    item = _decode(fields[2])
    # Re-encoding also rejects non-NFC input, untrimmed strings and hidden characters.
    if encode_lookup(fields[1], item, warehouse) != message:
        raise ValueError("Noncanonical wire request")
    return {"kind": fields[1], "item_text": item, "warehouse_name": warehouse}

"""Deterministic article/product/warehouse name resolution (offline core).

All inputs are *verified data* read from fixed NewBase OData entities by an
authorized SRV handler. This function cannot read 1C, choose OData URLs,
write anything, or infer missing inventory. Does not silently replace
missing balance rows with zero.
"""
from __future__ import annotations

from decimal import Decimal, InvalidOperation
import re

from .natural_stock_contract import validate_term

UUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\Z")
QTY = re.compile(r"-?[0-9]{1,9}(?:\.[0-9]{1,3})?\Z")
MAX_ITEMS = 2                  # $top=2, detects ambiguity
MAX_WAREHOUSES = 50           # SRV fetches $top=51 and rejects overflow
MAX_BALANCES = 50             # SRV fetches $top=51 and rejects overflow


def _ref(value: object) -> str:
    if not isinstance(value, str) or not UUID.fullmatch(value) or value == "00000000-0000-0000-0000-000000000000":
        raise ValueError("Invalid authoritative 1C GUID")
    return value


def _text(value: object, length: int = 160) -> str:
    return validate_term(value, max_length=length, label="1C field")


def _quantity(value: object) -> Decimal:
    if not isinstance(value, str) or not QTY.fullmatch(value):
        raise ValueError("Invalid authoritative 1C quantity")
    try:
        return Decimal(value)
    except InvalidOperation as exc:
        raise ValueError("Invalid quantity") from exc


def _status(status: str, **data: object) -> dict:
    return {"status": status, **data}


def resolve_stock(
    kind: str, item_text: str, warehouse_name: str | None,
    items: list[dict], warehouses: list[dict], balances: list[dict],
    *, item_query_complete: bool, warehouse_query_complete: bool,
    balance_query_complete: bool,
) -> dict:
    """Resolve only an exact article/name and optional real warehouse name.

    items have keys guid/article/name. warehouses: guid/name.
    balances: item_guid/warehouse_guid/quantity (decimal strings).
    Query-complete booleans are supplied by the OData handler after verifying
    that no nextLink, pagination, or cap could suppress matching rows.
    """
    if kind not in ("article", "name"):
        raise ValueError("Invalid kind")
    validate_term(item_text, max_length=96 if kind == "article" else 160, label="item")
    if warehouse_name is not None:
        validate_term(warehouse_name, max_length=100, label="warehouse")
    if not isinstance(items, list) or not isinstance(warehouses, list) or not isinstance(balances, list):
        raise ValueError("Invalid rows")
    if any(not isinstance(x, dict) for x in items+warehouses+balances):
        raise ValueError("Malformed records")
    if not item_query_complete or len(items) > MAX_ITEMS:
        return _status("ITEM_RESULT_INCOMPLETE")
    if not warehouse_query_complete or len(warehouses) > MAX_WAREHOUSES:
        return _status("WAREHOUSE_RESULT_INCOMPLETE")
    if not balance_query_complete or len(balances) > MAX_BALANCES:
        return _status("BALANCE_RESULT_INCOMPLETE")
    requested_field = "article" if kind == "article" else "name"
    matches = []
    for row in items:
        _ref(row.get("guid"))
        if not isinstance(row.get(requested_field), str):
            raise ValueError("Missing OData field")
        if row[requested_field] == item_text:
            matches.append(row)
    if not matches:
        return _status("ITEM_NOT_FOUND")
    if len(matches) > 1:
        return _status("ITEM_AMBIGUOUS")
    item = matches[0]
    item_guid = item["guid"]
    name = _text(item.get("name"))
    article = item.get("article")
    if article is not None:
        article = _text(article, 96)
    warehouse_by_guid = {}
    candidates = []
    for row in warehouses:
        guid = _ref(row.get("guid"))
        warehouse_title = _text(row.get("name"), 100)
        if guid in warehouse_by_guid:
            raise ValueError("Duplicate warehouse GUID")
        warehouse_by_guid[guid] = warehouse_title
        if warehouse_name is not None and warehouse_title == warehouse_name:
            candidates.append(guid)
    if warehouse_name is not None:
        if not candidates:
            return _status("WAREHOUSE_NOT_FOUND")
        if len(candidates) > 1:
            return _status("WAREHOUSE_AMBIGUOUS")
    selected = set(candidates) if warehouse_name is not None else set(warehouse_by_guid)
    if not selected:
        return _status("WAREHOUSES_UNAVAILABLE")
    found = []
    seen = set()
    for record in balances:
        if _ref(record.get("item_guid")) != item_guid:
            # Fixed server-side filter should have excluded unrelated items.
            raise ValueError("Unexpected item balance")
        warehouse_guid = _ref(record.get("warehouse_guid"))
        if warehouse_guid in seen:
            raise ValueError("Duplicate balance for warehouse")
        seen.add(warehouse_guid)
        if warehouse_guid not in warehouse_by_guid:
            return _status("WAREHOUSE_RESULT_INCOMPLETE")
        if warehouse_guid in selected:
            found.append({
                "warehouse": warehouse_by_guid[warehouse_guid],
                "quantity": _quantity(record.get("quantity"))
            })
    if not found:
        # A missing Balance record is not enough to claim an actual zero.
        return _status("NO_BALANCE_ROW")
    found.sort(key=lambda x: x["warehouse"])
    total = sum((row["quantity"] for row in found), Decimal(0))
    return _status(
        "PASS",
        item_name=name,
        article=article,
        scope="specified_warehouse" if warehouse_name is not None else "all_warehouses",
        warehouses=[{"name": r["warehouse"], "quantity": str(r["quantity"])} for r in found],
        total_quantity=str(total),
        source="1C NewBase Balance",
        mode="read-only",
    )

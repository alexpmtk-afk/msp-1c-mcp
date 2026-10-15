"""Read-only multi-card stock result for exact article OR product name.

A correct, complete OData query must return *every* matching catalog card.
Code is an internal 1C display field ONLY and is never a search selector.
All cards are returned with their own balance; no card is silently chosen.
No stock/warehouse GUID is exposed in the result.

A missing Balance row is displayed as a qualified zero per the user-facing
business rule, with an explicit NO_BALANCE_ROW marker. It must never be
misrepresented as a verified numeric-zero row.
"""
from __future__ import annotations

from decimal import Decimal, InvalidOperation
import re

from .natural_stock_contract import validate_term

UUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\\Z")
QTY = re.compile(r"-?[0-9]{1,9}(?:\.[0-9]{1,3})?\\Z")
MAX_ITEMS = 50            # 51st item is overflow, not silently truncated
MAX_WAREHOUSES = 50       # 51st warehouse is overflow
MAX_BALANCES = 2500       # 50 items x 50 warehouses max


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
    """Return all matching catalog cards, separately, with no GUID exposure.

    items: guid/article/name/code. warehouses: guid/name.
    balances: item_guid/warehouse_guid/quantity as decimal strings.

    The caller MUST verify complete, bounded OData enumeration for all
    matching items and their balances, including server-side pagination.
    A capped or incomplete result never returns an apparently valid subset.
    """
    if kind not in ("article", "name"):
        raise ValueError("Only article and name are searchable")
    validate_term(item_text, max_length=96 if kind == "article" else 160, label="item")
    if warehouse_name is not None:
        validate_term(warehouse_name, max_length=100, label="warehouse")
    if not isinstance(items, list) or not isinstance(warehouses, list) or not isinstance(balances, list):
        raise ValueError("Invalid rows")
    if any(not isinstance(row, dict) for row in items + warehouses + balances):
        raise ValueError("Malformed records")
    if not item_query_complete or len(items) > MAX_ITEMS:
        return _status("ITEM_RESULT_INCOMPLETE")
    if not warehouse_query_complete or len(warehouses) > MAX_WAREHOUSES:
        return _status("WAREHOUSE_RESULT_INCOMPLETE")
    if not balance_query_complete or len(balances) > MAX_BALANCES:
        return _status("BALANCE_RESULT_INCOMPLETE")

    items_by_guid = {}
    matching = []
    for row in items:
        guid = _ref(row.get("guid"))
        if guid in items_by_guid:
            raise ValueError("Repeated item GUID")
        name = _text(row.get("name"))
        article = row.get("article")
        code = row.get("code")
        if article is not None and article != "":
            article = _text(article, 96)
        else:
            article = None
        if code is not None and code != "":
            code = _text(code, 96)
        else:
            code = None
        normalized = {"guid": guid, "name": name, "article": article, "code": code}
        items_by_guid[guid] = normalized
        if normalized[kind] == item_text:
            matching.append(normalized)
    if not matching:
        return _status("ITEM_NOT_FOUND")

    warehouse_by_guid = {}
    warehouse_matches = []
    for row in warehouses:
        guid = _ref(row.get("guid"))
        if guid in warehouse_by_guid:
            raise ValueError("Repeated warehouse GUID")
        name = _text(row.get("name"), 100)
        warehouse_by_guid[guid] = name
        if warehouse_name is not None and name == warehouse_name:
            warehouse_matches.append(guid)
    if warehouse_name is not None:
        if not warehouse_matches:
            return _status("WAREHOUSE_NOT_FOUND")
        if len(warehouse_matches) > 1:
            return _status("WAREHOUSE_AMBIGUOUS")
        chosen_warehouses = set(warehouse_matches)
    else:
        chosen_warehouses = set(warehouse_by_guid)
    if not chosen_warehouses:
        return _status("WAREHOUSES_UNAVAILABLE")

    match_guids = {row["guid"] for row in matching}
    seen_pairs = set()
    stocks = {guid: [] for guid in match_guids}
    for record in balances:
        item_guid = _ref(record.get("item_guid"))
        unit_guid = _ref(record.get("warehouse_guid"))
        if item_guid not in match_guids:
            raise ValueError("Unexpected item Balance result")
        if unit_guid not in warehouse_by_guid:
            return _status("WAREHOUSE_RESULT_INCOMPLETE")
        pair = (item_guid, unit_guid)
        if pair in seen_pairs:
            raise ValueError("Duplicate item/warehouse Balance row")
        seen_pairs.add(pair)
        qty = _quantity(record.get("quantity"))
        if unit_guid in chosen_warehouses:
            stocks[item_guid].append({
                "name": warehouse_by_guid[unit_guid],
                "quantity": str(qty),
                "balance_state": "ROW_PRESENT",
            })

    # Each matching card is returned, even when it has no Balance rows.
    # Never sum different catalog cards together just because names match.
    results = []
    for row in matching:
        found = sorted(stocks[row["guid"]], key=lambda rec: rec["name"])
        has_rows = bool(found)
        if warehouse_name is not None and not found:
            found = [{
                "name": warehouse_name,
                "quantity": "0",
                "balance_state": "NO_BALANCE_ROW",
            }]
        total = sum((Decimal(entry["quantity"]) for entry in found), Decimal(0))
        results.append({
            "name": row["name"],
            "article": row["article"],
            "code": row["code"],
            "total_quantity": str(total),
            "balance_state": "HAS_BALANCE_ROWS" if has_rows else "NO_BALANCE_ROW",
            "warehouses": found,
        })
    # Preserve a deterministic presentation order while retaining every card.
    results.sort(key=lambda row: (row["name"], row["article"] or "", row["code"] or ""))
    output = _status(
        "PASS",
        search_kind=kind,
        search_term=item_text,
        scope="specified_warehouse" if warehouse_name is not None else "all_warehouses",
        requested_warehouse=warehouse_name,
        match_count=len(results),
        items=results,
        missing_balance_display_rule="0 means no Balance row when balance_state=NO_BALANCE_ROW; not an observed zero",
        source="1C NewBase Balance",
        mode="read-only",
    )
    # Retain existing single-card output fields; plural results never carry
    # an aggregated quantity that could conflate distinct catalog cards.
    if len(results) == 1:
        one = results[0]
        output.update({
            "item_name": one["name"],
            "article": one["article"],
            "code": one["code"],
            "total_quantity": one["total_quantity"],
            "warehouses": [
                {"name": x["name"], "quantity": x["quantity"]}
                for x in one["warehouses"]
            ],
            "balance_state": one["balance_state"],
        })
    return output

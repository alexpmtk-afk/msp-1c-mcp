"""Fail-closed adapter for fixed read-only NewBase OData JSON pages.

This module deliberately does NOT make HTTP calls. A future approved,
fixed-operation SRV relay can use its schema rules and supply authenticated
1C OData GET response bytes. Published entity/field names MUST first be
confirmed by the separate SRV metadata probe. No arbitrary OData gateway.
"""
from __future__ import annotations

from decimal import Decimal
import json
import re
from urllib.parse import quote

from .natural_stock_contract import validate_term
from .natural_stock_resolution import _ref, _quantity, _text

MAX_PAGE_BYTES = 262144
MAX_PRODUCT_ROWS = 51      # $top=51 to detect overflow of 50 matched cards
MAX_WAREHOUSE_ROWS = 51   # $top=51 => overflow; never return a partial total
MAX_BALANCE_ROWS = 2501  # $top=2501 detects overflow of 2500 pair rows


def exact_filter_url_fragment(field: str, text: str, *, approved_field: str) -> str:
    """Build only a fixed literal equality filter, not an arbitrary OData URL.

    The SRV metadata check must first prove approved_field is the correct 1C
    property for this operation. Never accept a property from model input.
    """
    if not isinstance(field, str) or not isinstance(approved_field, str):
        raise ValueError("Invalid field")
    if field != approved_field or field not in ("Description", "Артикул"):
        raise ValueError("Unapproved 1C lookup property")
    safe_text = validate_term(text, max_length=160, label="OData field")
    escaped = safe_text.replace("'", "''")
    return "$filter=" + quote(field + " eq '" + escaped + "'", safe="")


def _decode_page(raw: bytes | str, *, row_limit: int) -> tuple[list[dict], bool]:
    """Return rows and a completeness flag. Do not infer completeness from $top."""
    if isinstance(raw, str):
        raw = raw.encode("utf-8")
    if not isinstance(raw, bytes) or len(raw) > MAX_PAGE_BYTES:
        raise ValueError("OData page not bounded")
    try:
        payload = json.loads(raw.decode("utf-8"), parse_float=Decimal, parse_int=Decimal)
    except (UnicodeDecodeError, ValueError, TypeError) as exc:
        raise ValueError("Invalid OData JSON") from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("value"), list):
        raise ValueError("Missing OData value list")
    rows = payload["value"]
    if any(not isinstance(row, dict) for row in rows):
        raise ValueError("Unexpected OData rows")
    if len(rows) > row_limit:
        return ([], False)
    # 1C OData may return continuation under legacy or OData v4 naming.
    links = ("odata.nextLink", "@odata.nextLink", "__next", "nextLink")
    complete = not any(bool(payload.get(key)) for key in links)
    return rows, complete


def parse_item_page(
    raw: bytes | str, *,
    article_field: str | None,
) -> tuple[list[dict], bool]:
    """Read Ref_Key, Description, 1C Code and business article where published."""
    if article_field is not None and article_field != "Артикул":
        raise ValueError("Business article field requires schema approval")
    records, complete = _decode_page(raw, row_limit=MAX_PRODUCT_ROWS)
    if len(records) > 50:
        return [], False
    result = []
    for row in records:
        guid = _ref(row.get("Ref_Key"))
        name = _text(row.get("Description"))
        article = row.get(article_field) if article_field is not None else None
        # An empty published article is a legitimate missing value in NewBase.
        if article:
            article = _text(article, 96)
        else:
            article = None
        code = row.get("Code")
        if code:
            code = _text(code, 96)
        elif code == "" or code is None:
            code = None
        else:
            raise ValueError("Invalid 1C Code")
        result.append({"guid": guid, "name": name, "article": article, "code": code})
    return result, complete


def parse_warehouse_page(raw: bytes | str) -> tuple[list[dict], bool]:
    """Ref_Key + Description from a separately approved warehouse EntitySet."""
    records, complete = _decode_page(raw, row_limit=MAX_WAREHOUSE_ROWS)
    if len(records) > 50:  # $top=51 reliably finds overflow without paging
        return [], False
    result = [{
        "guid": _ref(row.get("Ref_Key")),
        "name": _text(row.get("Description"), 100)
    } for row in records]
    return result, complete


def parse_balance_page(raw: bytes | str) -> tuple[list[dict], bool]:
    """NewBase Balance with documented stock dimension properties."""
    records, complete = _decode_page(raw, row_limit=MAX_BALANCE_ROWS)
    if len(records) > 2500:
        return [], False
    result = []
    for row in records:
        value = row.get("КоличествоBalance")
        if isinstance(value, bool):
            raise ValueError("Invalid quantity")
        if isinstance(value, Decimal):
            value = format(value, "f")
        if not isinstance(value, str):
            raise ValueError("Invalid OData quantity type")
        quantity = _quantity(value)
        result.append({
            "item_guid": _ref(row.get("Номенклатура_Key")),
            "warehouse_guid": _ref(row.get("СтруктурнаяЕдиница_Key")),
            "quantity": str(quantity),
        })
    return result, complete

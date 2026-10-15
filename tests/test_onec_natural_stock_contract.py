import pytest

from msp_onec_mcp.natural_stock_contract import (
    decode_lookup,
    encode_lookup,
    validate_term,
)


def test_real_cyrillic_article_no_guid_all_warehouses():
    raw = "трн.02.034.9005.02.30"
    wire = encode_lookup("article", raw)
    assert wire.isascii()
    assert wire.startswith("LOOKUP1|article|")
    assert decode_lookup(wire) == {
        "kind": "article", "item_text": raw, "warehouse_name": None,
    }


def test_article_with_human_warehouse_name():
    decoded = decode_lookup(
        encode_lookup("article", "ТРН-02.12/900", "Основной склад")
    )
    assert decoded == {
        "kind": "article",
        "item_text": "ТРН-02.12/900",
        "warehouse_name": "Основной склад",
    }


def test_product_name_with_human_warehouse():
    decoded = decode_lookup(
        encode_lookup("name", "Лазерный комплект «Мастер»", "Склад готовой продукции")
    )
    assert decoded["item_text"] == "Лазерный комплект «Мастер»"
    assert decoded["warehouse_name"] == "Склад готовой продукции"
    assert decoded["kind"] == "name"


@pytest.mark.parametrize("kwargs", [
    {"kind": "wrong", "item_text": "SKU"},
    {"kind": "article", "item_text": ""},
    {"kind": "article", "item_text": " leading"},
    {"kind": "article", "item_text": "trailing "},
    {"kind": "article", "item_text": "A\nB"},
    {"kind": "article", "item_text": "A\u200bB"},
    {"kind": "article", "item_text": "A\x00B"},
    {"kind": "article", "item_text": "e\u0301"},
    {"kind": "article", "item_text": "x" * 97},
    {"kind": "name", "item_text": "x" * 161},
    {"kind": "article", "item_text": "A", "warehouse_name": ""},
    {"kind": "article", "item_text": "A", "warehouse_name": "X" * 101},
])
def test_reject_unsafe_or_ambiguous_terms(kwargs):
    with pytest.raises(ValueError):
        encode_lookup(**kwargs)


@pytest.mark.parametrize("wire", [
    "STOCK|uuid|uuid",
    "LOOKUP1|article|not+base64|-",
    "LOOKUP1|article|QQ==|-",
    "LOOKUP1|article|QQ|-|extra",
    "LOOKUP1|name||-",
    "LOOKUP1|article|QQ|",
    "LOOKUP1|article|QQ|aGk=",
    "LOOKUP2|article|QQ|-",
    "LOOKUP1|article|QQ|-|GET|/odata",
])
def test_reject_unknown_wire_or_injection(wire):
    with pytest.raises((ValueError, UnicodeError)):
        decode_lookup(wire)


def test_does_not_fuzzy_normalize_or_guess_sku():
    assert decode_lookup(encode_lookup("article", "TRN.01"))["item_text"] == "TRN.01"
    assert decode_lookup(encode_lookup("article", "trn.01"))["item_text"] == "trn.01"
    assert encode_lookup("article", "TRN.01") != encode_lookup("article", "trn.01")
    assert validate_term("Склад-01", max_length=100, label="warehouse") == "Склад-01"


def test_user_may_search_only_article_or_name_not_internal_code():
    with pytest.raises(ValueError):
        encode_lookup("code","НФ-00001359","Основной склад")
    with pytest.raises(ValueError):
        decode_lookup("LOOKUP1|code|0J3QpC0wMDAwMTM1OQ|-")
    assert decode_lookup(encode_lookup("name","Слэмбол 6 кг","Основной склад"))["kind"]=="name"

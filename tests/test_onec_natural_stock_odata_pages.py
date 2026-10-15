import json
from decimal import Decimal

import pytest

from msp_onec_mcp.natural_stock_odata_pages import (
    exact_filter_url_fragment, parse_item_page, parse_warehouse_page, parse_balance_page,
)
from msp_onec_mcp.natural_stock_resolution import resolve_stock

ITEM="11111111-2222-3333-4444-555555555555"
WH1="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
WH2="bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
ARTICLE="трн.02.034.9005.02.30"
NAME="Комплект «Мастер»"


def fixture(rows, **other):
    return json.dumps({"value":rows,**other},ensure_ascii=False).encode("utf-8")


def test_real_fields_complete_mock_e2e_article_all_warehouses():
    items, item_ok=parse_item_page(fixture([{
        "Ref_Key":ITEM,"Code":"НФ-00004217",
        "Description":NAME,"Артикул":ARTICLE
    }]),article_field="Артикул")
    warehouses, wh_ok=parse_warehouse_page(fixture([
        {"Ref_Key":WH1,"Description":"Основной склад"},
        {"Ref_Key":WH2,"Description":"Склад готовой продукции"},
    ]))
    balances, bal_ok=parse_balance_page(fixture([
        {"Номенклатура_Key":ITEM,"СтруктурнаяЕдиница_Key":WH1,"КоличествоBalance":6},
        {"Номенклатура_Key":ITEM,"СтруктурнаяЕдиница_Key":WH2,"КоличествоBalance":2.500},
    ]))
    answer=resolve_stock(
        "article",ARTICLE,None,items,warehouses,balances,
        item_query_complete=item_ok,warehouse_query_complete=wh_ok,
        balance_query_complete=bal_ok,
    )
    assert answer["status"]=="PASS"
    assert Decimal(answer["total_quantity"])==Decimal("8.500")
    assert answer["scope"]=="all_warehouses"
    assert {r["name"] for r in answer["warehouses"]}=={
        "Основной склад","Склад готовой продукции"
    }


def test_name_query_one_real_warehouse_without_article_field():
    items,item_ok=parse_item_page(fixture([{
        "Ref_Key":ITEM,"Description":NAME
    }]),article_field=None)
    warehouses,wh_ok=parse_warehouse_page(fixture([
        {"Ref_Key":WH1,"Description":"Основной склад"}
    ]))
    balances,balance_ok=parse_balance_page(fixture([
        {"Номенклатура_Key":ITEM,"СтруктурнаяЕдиница_Key":WH1,"КоличествоBalance":0},
    ]))
    result=resolve_stock(
        "name",NAME,"Основной склад",items,warehouses,balances,
        item_query_complete=item_ok,warehouse_query_complete=wh_ok,
        balance_query_complete=balance_ok,
    )
    assert result["status"]=="PASS"
    assert result["total_quantity"]=="0"
    assert result["article"] is None


def test_not_found_never_equivalent_to_zero():
    items,ok=parse_item_page(fixture([]),article_field="Артикул")
    assert items==[] and ok


def test_next_link_blocks_partial_stock_totals():
    rows=[{"Номенклатура_Key":ITEM,"СтруктурнаяЕдиница_Key":WH1,
           "КоличествоBalance":5}]
    _,complete=parse_balance_page(fixture(rows,**{"odata.nextLink":"NEXT"}))
    assert complete is False


def test_warehouse_page_cap_denies_partial_results():
    rows=[{"Ref_Key":WH1,"Description":"Основной склад"}]*51
    result,complete=parse_warehouse_page(fixture(rows))
    assert complete is False
    assert result==[]


def test_two_item_matches_remain_distinct():
    alt="22222222-3333-4444-5555-666666666666"
    items,complete=parse_item_page(fixture([
        {"Ref_Key":ITEM,"Description":NAME,"Артикул":ARTICLE},
        {"Ref_Key":alt,"Description":"Другая запись","Артикул":ARTICLE},
    ]),article_field="Артикул")
    assert complete is True
    assert len(items)==2


def test_exact_filter_escapes_quotes_and_unicode():
    flt=exact_filter_url_fragment("Артикул","трн.'Мастер'",approved_field="Артикул")
    assert flt.startswith("$filter=")
    assert "%D1%82" in flt
    assert "%27%27" in flt


@pytest.mark.parametrize("field,approved,value",[
    ("Name","Name","Товар"),
    ("Артикул","Code","ТРН"),
    ("Code","Code","x\nDELETE"),
    ("Description","Description"," leading"),
])
def test_refuse_unapproved_or_unsafe_filter(field,approved,value):
    with pytest.raises(ValueError):
        exact_filter_url_fragment(field,value,approved_field=approved)


@pytest.mark.parametrize("payload",[
    b"",
    b"{}",
    b'{"value":{}}',
    b'{"value":[null]}',
    b'{"value":[{"Ref_Key":"BAD","Description":"name"}]}',
    b'{"value":[]}' * 4000,
])
def test_bounded_json_and_schema(payload):
    with pytest.raises(ValueError):
        parse_item_page(payload,article_field=None)


def test_decimal_quantity_rejects_string_injection_or_bool():
    invalid=["NaN","1e300","1;DELETE",True]
    for value in invalid:
        with pytest.raises(ValueError):
            parse_balance_page(fixture([{
                "Номенклатура_Key":ITEM,"СтруктурнаяЕдиница_Key":WH1,
                "КоличествоBalance":value,
            }]))

from copy import deepcopy
import pytest

from msp_onec_mcp.natural_stock_resolution import resolve_stock

ITEM="11111111-2222-3333-4444-555555555555"
OTHER="22222222-3333-4444-5555-666666666666"
W1="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
W2="bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
ARTICLE="трн.02.034.9005.02.30"
NAME="Крепёжный комплект"
WAREHOUSES=[{"guid":W1,"name":"Основной склад"},{"guid":W2,"name":"Склад готовой продукции"}]
ITEMS=[{"guid":ITEM,"article":ARTICLE,"name":NAME}]
BALANCES=[
    {"item_guid":ITEM,"warehouse_guid":W1,"quantity":"12.500"},
    {"item_guid":ITEM,"warehouse_guid":W2,"quantity":"3"},
]


def resolve(kind="article", text=ARTICLE, warehouse=None, **overrides):
    opts={
        "items": ITEMS, "warehouses": WAREHOUSES, "balances": BALANCES,
        "item_query_complete":True,
        "warehouse_query_complete":True,
        "balance_query_complete":True,
    }
    opts.update(overrides)
    return resolve_stock(kind,text,warehouse,**opts)


def test_article_all_warehouses_exact_inventory():
    r=resolve()
    assert r["status"]=="PASS"
    assert r["article"]==ARTICLE
    assert r["item_name"]==NAME
    assert r["scope"]=="all_warehouses"
    assert r["total_quantity"]=="15.500"
    assert len(r["warehouses"])==2


def test_product_name_with_real_warehouse():
    r=resolve("name",NAME,"Основной склад")
    assert r["status"]=="PASS"
    assert r["total_quantity"]=="12.500"
    assert r["warehouses"]==[{"name":"Основной склад","quantity":"12.500"}]


def test_article_with_human_warehouse_exact():
    assert resolve(warehouse="Склад готовой продукции")["total_quantity"]=="3"
    assert resolve(warehouse="основной склад")["status"]=="WAREHOUSE_NOT_FOUND"


def test_no_match_never_fake_zero():
    assert resolve(text="missing")["status"]=="ITEM_NOT_FOUND"
    assert resolve(balances=[])["status"]=="NO_BALANCE_ROW"
    assert resolve(warehouses=[])["status"]=="WAREHOUSES_UNAVAILABLE"


def test_real_explicit_zero_is_not_missing():
    zero=[{"item_guid":ITEM,"warehouse_guid":W1,"quantity":"0"}]
    r=resolve(warehouse="Основной склад",balances=zero)
    assert r["status"]=="PASS"
    assert r["total_quantity"]=="0"


def test_ambiguous_product_article_or_name():
    second={"guid":OTHER,"article":ARTICLE,"name":"Другая позиция"}
    assert resolve(items=ITEMS+[second])["status"]=="ITEM_AMBIGUOUS"
    assert resolve("name",NAME,items=ITEMS+[{"guid":OTHER,"name":NAME,"article":"X"}])["status"]=="ITEM_AMBIGUOUS"


def test_duplicate_warehouse_names_are_ambiguous():
    warehouses=deepcopy(WAREHOUSES)
    warehouses[1]["name"]="Основной склад"
    assert resolve(warehouse="Основной склад",warehouses=warehouses)["status"]=="WAREHOUSE_AMBIGUOUS"


@pytest.mark.parametrize("flag,status",[
    ("item_query_complete","ITEM_RESULT_INCOMPLETE"),
    ("warehouse_query_complete","WAREHOUSE_RESULT_INCOMPLETE"),
    ("balance_query_complete","BALANCE_RESULT_INCOMPLETE"),
])
def test_pagination_or_incomplete_denied(flag,status):
    assert resolve(**{flag:False})["status"]==status


@pytest.mark.parametrize("row",[
    {"item_guid":OTHER,"warehouse_guid":W1,"quantity":"7"},
    {"item_guid":ITEM,"warehouse_guid":W1,"quantity":"NaN"},
    {"item_guid":ITEM,"warehouse_guid":W1,"quantity":"1e300"},
    {"item_guid":ITEM,"warehouse_guid":W1,"quantity":"99999999999"},
    {"item_guid":ITEM,"warehouse_guid":"INVALID","quantity":"2"},
])
def test_reject_corrupt_stock_rows(row):
    with pytest.raises(ValueError):
        resolve(balances=[row])


def test_reject_duplicate_balance_for_one_warehouse():
    with pytest.raises(ValueError):
        resolve(balances=[BALANCES[0],BALANCES[0]])


def test_reject_unmapped_warehouse():
    third="cccccccc-dddd-eeee-ffff-aaaaaaaaaaaa"
    r=resolve(balances=[{"item_guid":ITEM,"warehouse_guid":third,"quantity":"4"}])
    assert r["status"]=="WAREHOUSE_RESULT_INCOMPLETE"


def test_no_fuzzy_or_marketplace_fallback():
    assert resolve("article",ARTICLE.upper())["status"]=="ITEM_NOT_FOUND"
    assert resolve("name","Крепёжный комлект")["status"]=="ITEM_NOT_FOUND"


def test_cap_never_reports_partial_total():
    records=[{"item_guid":ITEM,"warehouse_guid":W1,"quantity":"1"}]*51
    assert resolve(balances=records)["status"]=="BALANCE_RESULT_INCOMPLETE"

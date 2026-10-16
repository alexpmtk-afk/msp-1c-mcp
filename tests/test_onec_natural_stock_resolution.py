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
    empty=resolve(balances=[])
    assert empty["status"]=="PASS"
    assert empty["items"][0]["total_quantity"]=="0"
    assert empty["items"][0]["balance_state"]=="NO_BALANCE_ROW"
    assert resolve(warehouses=[])["status"]=="WAREHOUSES_UNAVAILABLE"


def test_real_explicit_zero_is_not_missing():
    zero=[{"item_guid":ITEM,"warehouse_guid":W1,"quantity":"0"}]
    r=resolve(warehouse="Основной склад",balances=zero)
    assert r["status"]=="PASS"
    assert r["total_quantity"]=="0"


def test_ambiguous_product_article_or_name():
    second={"guid":OTHER,"article":ARTICLE,"name":"Другая позиция"}
    by_article=resolve(items=ITEMS+[second])
    assert by_article["status"]=="PASS"
    assert by_article["match_count"]==2
    assert [x["total_quantity"] for x in by_article["items"]]==["0","15.500"] or sorted(x["total_quantity"] for x in by_article["items"])==["0","15.500"]
    by_name=resolve("name",NAME,items=ITEMS+[{"guid":OTHER,"name":NAME,"article":"X"}])
    assert by_name["status"]=="PASS"
    assert by_name["match_count"]==2


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
    records=[{"item_guid":ITEM,"warehouse_guid":W1,"quantity":"1"}]*2501
    assert resolve(balances=records)["status"]=="BALANCE_RESULT_INCOMPLETE"


def test_live_newbase_duplicate_slam_ball_names_return_both_balances():
    first={"guid":ITEM,"name":"Слэмбол 6 кг","code":"НФ-00001359","article":None}
    second={"guid":OTHER,"name":"Слэмбол 6 кг","code":"НФ-00000879","article":None}
    stock=[{"item_guid":ITEM,"warehouse_guid":W1,"quantity":"6"}]
    result=resolve("name","Слэмбол 6 кг","Основной склад",
                   items=[first,second],balances=stock)
    assert result["status"]=="PASS"
    assert result["match_count"]==2
    assert "total_quantity" not in result  # never sum distinct 1C cards
    assert ITEM not in repr(result) and OTHER not in repr(result)
    by_code={row["code"]:row for row in result["items"]}
    assert by_code["НФ-00001359"]["total_quantity"]=="6"
    assert by_code["НФ-00001359"]["balance_state"]=="HAS_BALANCE_ROWS"
    assert by_code["НФ-00000879"]["total_quantity"]=="0"
    assert by_code["НФ-00000879"]["balance_state"]=="NO_BALANCE_ROW"
    assert by_code["НФ-00000879"]["warehouses"]==[
        {"name":"Основной склад","quantity":"0","balance_state":"NO_BALANCE_ROW"}]
    assert all(row["article"] is None for row in result["items"])
    assert "not an observed zero" in result["missing_balance_display_rule"]


def test_missing_article_not_searchable_but_name_is():
    item={"guid":ITEM,"name":"Слэмбол 6 кг","code":"НФ-00001359","article":None}
    assert resolve("article","ТРН-99",items=[item])["status"]=="ITEM_NOT_FOUND"
    assert resolve("name","Слэмбол 6 кг",items=[item])["status"]=="PASS"
    with pytest.raises(ValueError):
        resolve("code","НФ-00001359",items=[item])


def test_ten_cards_with_same_name_are_all_returned():
    rows=[]
    stock=[]
    for n in range(1,11):
        guid=f"{n:08x}-2222-3333-4444-555555555555"
        rows.append({"guid":guid,"name":"Слэмбол 6 кг",
                     "article":None,"code":f"НФ-{n:08d}"})
        if n%2 == 0:
            stock.append({"item_guid":guid,"warehouse_guid":W1,
                          "quantity":str(n)})
    result=resolve("name","Слэмбол 6 кг","Основной склад",
                   items=rows,balances=stock)
    assert result["status"]=="PASS"
    assert result["match_count"]==10
    assert len(result["items"])==10
    assert sorted(row["total_quantity"] for row in result["items"])==sorted(
        ["0" if n%2 else str(n) for n in range(1,11)])
    assert "total_quantity" not in result


def test_fifty_matches_accepted_fifty_one_is_incomplete():
    rows=[{"guid":f"{n:08x}-2222-3333-4444-555555555555",
           "name":"Одинаковый товар","article":"A-1",
           "code":f"НФ-{n:08d}"} for n in range(1,52)]
    fifty=resolve("article","A-1",warehouse="Основной склад",
                  items=rows[:50],balances=[])
    assert fifty["status"]=="PASS"
    assert fifty["match_count"]==50
    assert resolve("article","A-1",items=rows)["status"]=="ITEM_RESULT_INCOMPLETE"


def test_same_article_different_names_returns_each_row_separately():
    items=[{"guid":ITEM,"name":"Коврик А","article":"ART123","code":"НФ-00000123"},
           {"guid":OTHER,"name":"Коврик Б","article":"ART123","code":"НФ-00000456"}]
    answer=resolve("article","ART123","Основной склад",items=items,
                   balances=[{"item_guid":ITEM,"warehouse_guid":W1,"quantity":"1"}])
    assert answer["status"]=="PASS"
    assert answer["match_count"]==2
    assert [r["name"] for r in answer["items"]]==["Коврик А","Коврик Б"]
    assert [r["total_quantity"] for r in answer["items"]]==["1","0"]

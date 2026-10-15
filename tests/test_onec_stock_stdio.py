import json
from unittest.mock import patch

from msp_onec_mcp import onec_stock_stdio as m


def test_initialize_and_discovery():
    start=m.dispatch({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}})
    assert start["result"]["protocolVersion"]=="2025-06-18"
    tools=m.dispatch({"jsonrpc":"2.0","id":2,"method":"tools/list"})["result"]["tools"]
    assert len(tools)==2
    assert [t["name"] for t in tools]==["onec_stock_by_guid","onec_stock_by_name_or_article"]
    assert tools[0]["name"]=="onec_stock_by_guid"
    assert tools[0]["inputSchema"]["additionalProperties"] is False
    annotations=tools[0]["annotations"]
    assert annotations=={
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    }


def test_selected_stock_call_and_invalid_params():
    guid1="11111111-2222-3333-4444-555555555555"
    guid2="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    params={"name":"onec_stock_by_guid","arguments":{"item_guid":guid1,"warehouse_guid":guid2}}
    with patch.object(m,"selected_stock",return_value={"status":"PASS","quantity":"6"}) as stock:
        response=m.dispatch({"jsonrpc":"2.0","id":3,"method":"tools/call","params":params})
    assert response["result"]["isError"] is False
    assert json.loads(response["result"]["content"][0]["text"])["quantity"]=="6"
    stock.assert_called_once_with(guid1,guid2)
    for args in ({"item_guid":guid1},{"item_guid":guid1,"warehouse_guid":guid2,"command":"id"}):
        bad=m.dispatch({"jsonrpc":"2.0","id":4,"method":"tools/call","params":{
            "name":"onec_stock_by_guid","arguments":args
        }})
        assert bad["result"]["isError"] is True
        assert "INVALID_ARGUMENTS" in bad["result"]["content"][0]["text"]


def test_notifications_and_unknown_methods():
    assert m.dispatch({"jsonrpc":"2.0","method":"notifications/initialized"}) is None
    assert m.dispatch({"jsonrpc":"2.0","id":5,"method":"tools/execute"})["error"]["code"]==-32601


def test_natural_tool_returns_all_item_cards_without_requiring_internal_code():
    params={"name":"onec_stock_by_name_or_article",
            "arguments":{"kind":"name","query":"Слэмбол 6 кг",
                         "warehouse_name":"Основной склад"}}
    result={"status":"PASS","match_count":2,"items":[
        {"name":"Слэмбол 6 кг","code":"НФ-00001359","article":None,"total_quantity":"6"},
        {"name":"Слэмбол 6 кг","code":"НФ-00000879","article":None,
         "total_quantity":"0","balance_state":"NO_BALANCE_ROW"}]}
    with patch.object(m,"natural_stock",return_value=result) as lookup:
        response=m.dispatch({"jsonrpc":"2.0","id":11,"method":"tools/call","params":params})
    assert response["result"]["isError"] is False
    parsed=json.loads(response["result"]["content"][0]["text"])
    assert parsed["match_count"]==2
    assert [x["total_quantity"] for x in parsed["items"]]==["6","0"]
    lookup.assert_called_once_with("name","Слэмбол 6 кг","Основной склад")


def test_natural_tool_rejects_internal_code_selector_and_extra_arguments():
    bad_requests=[
        {"kind":"code","query":"НФ-00001359"},
        {"kind":"name","query":"Слэмбол 6 кг","command":"system"},
        {"kind":"article"},
        {"kind":"name","query":"Слэмбол 6 кг","item_guid":"x"},
    ]
    for args in bad_requests:
        response=m.dispatch({"jsonrpc":"2.0","id":12,"method":"tools/call","params":{
            "name":"onec_stock_by_name_or_article","arguments":args}})
        assert response["result"]["isError"] is True
        assert "INVALID_ARGUMENTS" in response["result"]["content"][0]["text"]

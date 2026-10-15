import json
from unittest.mock import patch

from msp_onec_mcp import onec_stock_stdio as m


def test_initialize_and_discovery():
    start=m.dispatch({"jsonrpc":"2.0","id":1,"method":"initialize","params":{}})
    assert start["result"]["protocolVersion"]=="2025-06-18"
    tools=m.dispatch({"jsonrpc":"2.0","id":2,"method":"tools/list"})["result"]["tools"]
    assert len(tools)==1
    assert tools[0]["name"]=="onec_stock_by_guid"
    assert tools[0]["inputSchema"]["additionalProperties"] is False


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

"""Opt-in MCP frontend goes through the loopback natural queue only."""
import json
from unittest.mock import patch
import os

import pytest
from msp_onec_mcp.natural_stock_vps import natural_stock

TOKEN="x"*48
ID="a"*32
LEASE="b"*32


class FakeResponse:
    def __init__(self, text, status=200):
        self.status=status
        self.content=text if isinstance(text, bytes) else text.encode("utf-8")
    def read(self,limit):
        return self.content[:limit]
    def __enter__(self):
        return self
    def __exit__(self,*args):
        return False


def fake_reply(req,timeout):
    assert timeout==8
    assert req.full_url.startswith("http://127.0.0.1:9786/")
    assert req.get_header("Authorization")=="Bearer "+TOKEN
    if req.full_url.endswith("/v1/admin/enqueue-natural"):
        assert req.get_method()=="POST"
        assert req.data.startswith(b"LOOKUP1|name|")
        return FakeResponse("ENQUEUED|"+ID,201)
    if req.full_url.endswith("/v1/admin/status/"+ID):
        return FakeResponse("STATUS|"+ID+"|done|NATURAL_RESULT")
    assert req.full_url.endswith("/v1/admin/natural-result/"+ID)
    return FakeResponse(json.dumps({
        "status":"PASS","search_kind":"name","search_term":"Слэмбол 6 кг",
        "requested_warehouse":"Основной склад","match_count":2,
        "items":[
            {"name":"Слэмбол 6 кг","code":"НФ-00001359","article":None,
             "total_quantity":"6","balance_state":"HAS_BALANCE_ROWS",
             "warehouses":[{"name":"Основной склад","quantity":"6","balance_state":"ROW_PRESENT"}]},
            {"name":"Слэмбол 6 кг","code":"НФ-00000879","article":None,
             "total_quantity":"0","balance_state":"NO_BALANCE_ROW",
             "warehouses":[{"name":"Основной склад","quantity":"0","balance_state":"NO_BALANCE_ROW"}]},
        ],"source":"1C NewBase Balance","mode":"read-only",
    },ensure_ascii=False))


def test_native_mcp_nat_stock_tool_requires_explicit_enable():
    with patch.dict(os.environ,{"ONEC_ENABLE_NATURAL_STOCK":"0"}):
        assert natural_stock("name","Слэмбол 6 кг")["status"]=="DISABLED"


def test_onec_native_multi_card_result_is_returned_unchanged():
    with patch.dict(os.environ,{"ONEC_ENABLE_NATURAL_STOCK":"1",
                                "ONEC_OPERATOR_TOKEN":TOKEN,"ONEC_RELAY_PORT":"9786"}), \
         patch("msp_onec_mcp.natural_stock_vps.urlopen",side_effect=fake_reply), \
         patch("msp_onec_mcp.natural_stock_vps.time.sleep",return_value=None):
        answer=natural_stock("name","Слэмбол 6 кг","Основной склад")
    assert answer["status"]=="PASS"
    assert answer["match_count"]==2
    assert [x["total_quantity"] for x in answer["items"]]==["6","0"]
    assert answer["items"][1]["balance_state"]=="NO_BALANCE_ROW"


@pytest.mark.parametrize("kind,query",[
    ("code","НФ-00001359"),("name","Слэмбол 6 кг\nmalicious"),
    ("article","  ABC"),
])
def test_reject_unsafe_lookup_before_network(kind,query):
    with patch("msp_onec_mcp.natural_stock_vps.urlopen") as network:
        with pytest.raises(ValueError):
            natural_stock(kind,query)
    network.assert_not_called()


def test_invalid_local_port_cannot_trigger_network():
    with patch.dict(os.environ,{"ONEC_ENABLE_NATURAL_STOCK":"1",
                                "ONEC_OPERATOR_TOKEN":TOKEN,"ONEC_RELAY_PORT":"9786;ignored"}):
        assert natural_stock("name","Слэмбол 6 кг")["status"]=="UNCONFIGURED"

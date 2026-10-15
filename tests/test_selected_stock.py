from __future__ import annotations

import os
from unittest.mock import patch

import pytest

from msp_onec_mcp.selected_stock import selected_stock, validate_guid

ITEM = "11111111-2222-3333-4444-555555555555"
WAREHOUSE = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
JOB = "a" * 32
LEASE = "b" * 32
TOKEN = "c" * 40


class FakeResponse:
    def __init__(self, content: str, status: int = 200):
        self.status = status
        self.content = content.encode("ascii")
    def read(self, limit: int) -> bytes:
        return self.content[:limit]
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return None


def queue(status_result: str):
    requests = []
    def opener(req, timeout):
        assert timeout == 8
        assert req.full_url.startswith("http://127.0.0.1:9786/")
        assert req.get_header("Authorization") == "Bearer " + TOKEN
        requests.append((req.get_method(), req.full_url, req.data))
        if req.full_url.endswith("/v1/admin/enqueue-selected"):
            assert req.data == ("STOCK|" + ITEM + "|" + WAREHOUSE).encode("ascii")
            return FakeResponse("ENQUEUED|" + JOB, 201)
        assert req.full_url.endswith("/v1/admin/status/" + JOB)
        return FakeResponse("STATUS|" + JOB + "|done|RESULT|" + JOB + "|" + LEASE + "|" + status_result)
    return opener, requests


@pytest.mark.parametrize("invalid", [
    "", "Z", ITEM.upper(), "00000000-0000-0000-0000-000000000000",
    ITEM + ";rm -rf /", "../" + ITEM, "STOCK|" + ITEM, ITEM + "\n",
    "g" * 36, "a" * 200,
])
def test_strict_guid_validation(invalid):
    with pytest.raises(ValueError):
        validate_guid(invalid)


def test_requires_explicit_enable_even_with_credentials():
    with patch.dict(os.environ, {"ONEC_OPERATOR_TOKEN": TOKEN, "ONEC_ENABLE_STOCK_SELECTED": "0"}):
        assert selected_stock(ITEM, WAREHOUSE)["status"] == "DISABLED"


def test_valid_selected_quantity_is_bounded():
    fn, requests = queue("PASS|SELECTED_Q_6.125")
    with patch.dict(os.environ, {"ONEC_OPERATOR_TOKEN": TOKEN, "ONEC_ENABLE_STOCK_SELECTED": "1", "ONEC_RELAY_PORT": "9786"}), \
         patch("msp_onec_mcp.selected_stock.urlopen", side_effect=fn), \
         patch("msp_onec_mcp.selected_stock.time.sleep", return_value=None):
        response = selected_stock(ITEM, WAREHOUSE)
    assert response == {"status": "PASS", "quantity": "6.125", "source": "1C NewBase Balance", "mode": "read-only"}
    assert len(requests) == 2
    assert requests[0][0] == "POST"
    assert requests[1][0] == "GET"
    assert not any(ITEM in str(v) or WAREHOUSE in str(v) for v in response.values())


def test_negative_absence_is_not_zero_stock():
    fn, _ = queue("FAIL|ODATA_SELECTED_NO_ROW")
    with patch.dict(os.environ, {"ONEC_OPERATOR_TOKEN": TOKEN, "ONEC_ENABLE_STOCK_SELECTED": "1", "ONEC_RELAY_PORT": "9786"}), \
         patch("msp_onec_mcp.selected_stock.urlopen", side_effect=fn), \
         patch("msp_onec_mcp.selected_stock.time.sleep", return_value=None):
        response = selected_stock(ITEM, WAREHOUSE)
    assert response == {"status": "FAIL", "error_code": "ODATA_SELECTED_NO_ROW"}


def test_forbids_other_operation_result_and_secrets():
    fn, _ = queue("PASS|STOCK_Q_6")
    with patch.dict(os.environ, {"ONEC_OPERATOR_TOKEN": TOKEN, "ONEC_ENABLE_STOCK_SELECTED": "1", "ONEC_RELAY_PORT": "9786"}), \
         patch("msp_onec_mcp.selected_stock.urlopen", side_effect=fn), \
         patch("msp_onec_mcp.selected_stock.time.sleep", return_value=None):
        response = selected_stock(ITEM, WAREHOUSE)
    assert response == {"status": "FAIL", "error_code": "UNEXPECTED_RESULT"}
    assert TOKEN not in str(response)


def test_invalid_local_port_is_not_used():
    with patch.dict(os.environ, {"ONEC_OPERATOR_TOKEN": TOKEN, "ONEC_ENABLE_STOCK_SELECTED": "1", "ONEC_RELAY_PORT": "9786;attack"}):
        assert selected_stock(ITEM, WAREHOUSE)["status"] == "UNCONFIGURED"


def test_no_credential_does_not_issue_network_requests():
    with patch.dict(os.environ, {"ONEC_OPERATOR_TOKEN": "", "ONEC_ENABLE_STOCK_SELECTED": "1"}):
        assert selected_stock(ITEM, WAREHOUSE)["status"] == "UNCONFIGURED"

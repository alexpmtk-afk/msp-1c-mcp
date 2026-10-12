import httpx
import pytest

from msp_onec_mcp.client import OneCReadOnlyClient
from msp_onec_mcp.config import OneCConfig
from msp_onec_mcp.metadata import inspect_metadata

SAMPLE = b'''<?xml version="1.0"?>
<edmx:Edmx xmlns:edmx="http://schemas.microsoft.com/ado/2007/06/edmx"
 xmlns="http://schemas.microsoft.com/ado/2008/09/edm">
 <edmx:DataServices>
  <Schema Namespace="StandardODATA">
   <EntityType Name="Catalog_Goods"><Property Name="Ref_Key" Type="Edm.Guid"/><Property Name="Description" Type="Edm.String"/></EntityType>
   <EntityContainer Name="EntityContainer"><EntitySet Name="Catalog_Goods" EntityType="StandardODATA.Catalog_Goods"/></EntityContainer>
  </Schema>
 </edmx:DataServices>
</edmx:Edmx>'''


def test_parse_summary():
    result = inspect_metadata(SAMPLE)
    assert result["entity_set_count"] == 1
    assert result["entities"][0]["property_count"] == 2
    assert result["entities"][0]["name"] == "Catalog_Goods"


def test_reject_xml_dtd():
    evil = b'<!DOCTYPE x [<!ENTITY a "something">]><Schema xmlns="ns" Namespace="X"/>'
    with pytest.raises(Exception):
        inspect_metadata(evil)


def test_client_uses_only_metadata_get():
    calls = []
    def handle(request):
        calls.append((request.method, str(request.url)))
        return httpx.Response(200, content=SAMPLE)
    cfg = OneCConfig("https://onec.example.invalid/odata/standard.odata", "user", "secret")
    response = OneCReadOnlyClient(cfg, transport=httpx.MockTransport(handle)).inspect()
    assert response["entity_set_count"] == 1
    assert calls == [("GET", "https://onec.example.invalid/odata/standard.odata/$metadata")]


def test_no_redirect_to_untrusted_host():
    def handle(request):
        return httpx.Response(302, headers={"Location": "https://external.invalid/collect"})
    cfg = OneCConfig("https://onec.example.invalid/odata/standard.odata", "user", "secret")
    with pytest.raises(httpx.HTTPStatusError):
        OneCReadOnlyClient(cfg, transport=httpx.MockTransport(handle)).inspect()

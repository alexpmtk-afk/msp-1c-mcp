import pytest

from msp_onec_mcp.config import ConfigurationError, OneCConfig, config_presence


def test_secure_config():
    cfg = OneCConfig("https://onec.example.invalid/odata/standard.odata", "service", "secret")
    assert cfg.metadata_url.endswith("/odata/standard.odata/$metadata")


@pytest.mark.parametrize("url", [
    "http://host/odata/standard.odata",
    "https://u:password@host/odata/standard.odata",
    "https://host/not_odata",
    "https://host/odata/standard.odata?x=y",
])
def test_reject_unsafe_base_url(url):
    with pytest.raises(ConfigurationError):
        OneCConfig(url, "service", "secret")


def test_presence_does_not_expose_secret(monkeypatch):
    monkeypatch.setenv("ONEC_PASSWORD", "top-secret")
    result = config_presence()
    assert "top-secret" not in str(result)
    assert result["password_configured"] is True

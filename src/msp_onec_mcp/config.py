"""Connection configuration: no guessing, no implicit insecure fallbacks."""

from __future__ import annotations

from dataclasses import dataclass
import os
from urllib.parse import urlsplit


class ConfigurationError(ValueError):
    pass


@dataclass(frozen=True)
class OneCConfig:
    odata_base_url: str
    username: str
    password: str

    def __post_init__(self) -> None:
        u = urlsplit(self.odata_base_url)
        if (
            u.scheme != "https"
            or not u.hostname
            or u.username is not None
            or u.password is not None
            or u.query
            or u.fragment
            or not u.path.rstrip("/").lower().endswith("/odata/standard.odata")
        ):
            raise ConfigurationError(
                "ONEC_ODATA_BASE_URL must be an HTTPS OData root without credentials, query or fragment"
            )
        if not self.username or not self.password:
            raise ConfigurationError("Separate ONEC_USERNAME and ONEC_PASSWORD are required")

    @classmethod
    def from_env(cls) -> "OneCConfig":
        return cls(
            (os.getenv("ONEC_ODATA_BASE_URL") or "").strip(),
            os.getenv("ONEC_USERNAME") or "",
            os.getenv("ONEC_PASSWORD") or "",
        )

    @property
    def metadata_url(self) -> str:
        return self.odata_base_url.rstrip("/") + "/$metadata"


def config_presence() -> dict[str, bool]:
    """Return *presence only*; never disclose credentials or endpoint."""
    return {
        "odata_endpoint_configured": bool(os.getenv("ONEC_ODATA_BASE_URL")),
        "username_configured": bool(os.getenv("ONEC_USERNAME")),
        "password_configured": bool(os.getenv("ONEC_PASSWORD")),
    }

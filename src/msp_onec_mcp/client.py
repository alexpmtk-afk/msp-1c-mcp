"""Restricted HTTPS client: only GET $metadata is supported in Phase 1."""

from __future__ import annotations

import httpx

from .config import OneCConfig
from .metadata import inspect_metadata


MAX_METADATA_BYTES = 16 * 1024 * 1024


class OneCReadOnlyClient:
    def __init__(self, config: OneCConfig, *, transport: httpx.BaseTransport | None = None):
        self.config = config
        self.transport = transport

    def inspect(self, *, limit: int = 50) -> dict:
        if not 1 <= limit <= 100:
            raise ValueError("limit must be between 1 and 100")
        with httpx.Client(
            auth=httpx.BasicAuth(self.config.username, self.config.password),
            timeout=httpx.Timeout(15.0),
            verify=True,
            follow_redirects=False,
            trust_env=False,
            transport=self.transport,
        ) as client:
            with client.stream("GET", self.config.metadata_url, headers={"Accept": "application/xml"}) as resp:
                resp.raise_for_status()
                buf = bytearray()
                for chunk in resp.iter_bytes():
                    buf.extend(chunk)
                    if len(buf) > MAX_METADATA_BYTES:
                        raise ValueError("OData metadata exceeds configured size limit")
        return inspect_metadata(bytes(buf), limit=limit)

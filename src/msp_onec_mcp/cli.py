"""CLI designed for a versioned, whitelisted runner job."""

from __future__ import annotations

import argparse
import json

import httpx
from defusedxml.common import DefusedXmlException
from xml.etree.ElementTree import ParseError

from .client import OneCReadOnlyClient
from .config import ConfigurationError, OneCConfig, config_presence


def safe_probe(limit: int = 50) -> dict:
    try:
        data = OneCReadOnlyClient(OneCConfig.from_env()).inspect(limit=limit)
    except ConfigurationError:
        return {"status": "not_configured", "detail": "Check local environment variables"}
    except httpx.HTTPStatusError as exc:
        return {"status": "http_error", "http_status": exc.response.status_code}
    except httpx.HTTPError:
        return {"status": "connection_error", "detail": "Connection/TLS/auth transport failed"}
    except (ValueError, LookupError, ParseError, DefusedXmlException) as exc:
        return {"status": "metadata_error", "detail": type(exc).__name__}
    return {"status": "ok", "metadata": data}


def main() -> int:
    parser = argparse.ArgumentParser(description="MSP 1C safe diagnostics (read-only)")
    parser.add_argument("command", choices=["config", "probe"])
    parser.add_argument("--limit", type=int, default=50)
    args = parser.parse_args()
    result = (
        {"status": "ok", "configuration": config_presence()}
        if args.command == "config"
        else safe_probe(limit=args.limit)
    )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0 if result["status"] == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())

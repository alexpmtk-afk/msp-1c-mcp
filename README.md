# msp-1c-mcp

**Status: D0 — initial MCP connector scaffold. No connection to a live 1C infobase has been established.**

A dedicated integration for **1С:Предприятие 8.5.1.1302 / УНФ 3.0.13.314** (versions reported by the project owner; not independently verified).

## Purpose

- Explore the actual 1C configuration programmatically from ChatGPT, **without Hermes** in the research loop.
- Begin with safe, read-only OData metadata diagnostics.
- Gradually implement and independently test stock, invoice and shipment MCP tools.
- Integrate the verified MCP server into the existing `msp-server-stack` on REMOTE.

## What is implemented

- Read-only MCP STDIO tools: `onec_connection_configured`, `onec_metadata_overview`.
- Fixed-command CLI: `config` and `probe`.
- Defensive HTTPS/OData client, bounded XML metadata summary, offline tests.

**Not implemented:** network access to your 1C, OData publication, GitHub-to-1C runner bridge operation, invoice/shipment creation or posting. No production 1C actions are authorized.

## Local development

```bash
python -m venv .venv
. .venv/bin/activate
python -m pip install -e '.[dev]'
pytest -q
python -m msp_onec_mcp.cli config
```

On Windows PowerShell activate with `.venv\\Scripts\\Activate.ps1`.

## Approved read-only probe (only after secure endpoint and service account exist)

Configure `ONEC_ODATA_BASE_URL`, `ONEC_USERNAME` and `ONEC_PASSWORD` **outside Git**, as described by `.env.example`. Require a validated HTTPS endpoint ending in `/odata/standard.odata`.

```bash
python -m msp_onec_mcp.cli probe --limit 20
```

The probe requests **only** `GET /odata/standard.odata/$metadata`, then produces a bounded summary. TLS verification is enabled, redirects are rejected; no document writes are supported.

To run the STDIO MCP server in a trusted, configured environment:

```bash
msp-onec-mcp
```

## Repositories and secret boundaries

- `msp-1c-mcp` (PUBLIC): 1C connector code, MCP tools, metadata semantics, safe test fixtures and versioned procedures.
- `msp-server-stack` (PUBLIC): canonical REMOTE infrastructure, inventory and deployment documentation.
- `msp-server-bridge` (PRIVATE): existing whitelisted GitHub Actions → REMOTE execution channel.
- Credentials, database copies, private endpoints and operational records remain **outside public Git**, e.g. protected `/opt/mcp/secrets/onec.env` on REMOTE.

See [architecture](docs/ARCHITECTURE.md), [security](docs/SECURITY.md), [roadmap](docs/ROADMAP.md) and [tool catalog](config/tool_catalog.yaml).

## References

- [1C platform documentation](https://its.1c.ru/db/v851doc/bookmark/dev/TI000000783)
- [1C OData publication documentation](https://kb.1ci.com/1C_Enterprise_Platform/FAQ/Development/Integration/Publishing_standard_REST_API_for_your_infobase/?language=en)

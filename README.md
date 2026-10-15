# msp-1c-mcp

**Status (2026-10-15): read-only NewBase stock MCP via GitHub → VPS → SRV → local OData is deployed and live-accepted. Production 1C remains untouched.**

A dedicated integration for **1С:Предприятие 8.5.1.1302 / УНФ 3.0.13.314** (versions reported by the project owner; not independently verified).

## Purpose

- Explore the actual 1C configuration programmatically from ChatGPT, **without Hermes** in the research loop.
- Begin with safe, read-only OData metadata diagnostics.
- Gradually implement and independently test stock, invoice and shipment MCP tools.
- Integrate the verified MCP server into the existing `msp-server-stack` on REMOTE.

## What is implemented

- Original diagnostic STDIO tools: `onec_connection_configured`, `onec_metadata_overview` (their direct remote OData metadata route is separate and not certified by this rollout).
- **Deployed on VPS:** isolated STDIO MCP `onec-stock`, exposing `onec_stock_by_guid(item_guid, warehouse_guid)` for one read-only Balance quantity in test `NewBase`.
- Agent transport: private GitHub Issue → VPS loopback queue → LocalService SRV poller → HTTP GET via `127.0.0.1:8085/NewBase/odata/standard.odata` → result.
- Offline tests, pinned deployment, both Codex configs, MCP `initialize`, `tools/list`, and live `tools/call` for the tested GUID pair: **PASS; quantity 6**.

**Not implemented:** free-form product/warehouse search by name, generalized metadata integration, invoices or shipment creation/posting, production 1C actions. No writes are authorized.


## Live read-only stock MCP (2026-10-15)

On REMOTE, Codex main and dashboard configs have one additional entry, `onec-stock`, run by `/home/hermes/.local/share/onec-stock-mcp/run-onec-stock-mcp.sh`. The isolated adapter uses system Python and the existing local 1C relay; it does not require `mcp` to be installed in system Python and does not change the Hermes service.

The only exposed tool is `onec_stock_by_guid`. Inputs are lowercase canonical, nonzero 1C item and warehouse GUIDs. It returns a bounded read-only quantity or a classified error; there is no arbitrary URL, command, query string, shell, COM or writes. Example shape:

```json
{"item_guid":"11111111-2222-3333-4444-555555555555","warehouse_guid":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}
```

The GUIDs above are synthetic format examples, not inventory references. A real selected-pair read returned quantity 6 through MCP and matched a previously confirmed local OData GET.

Acceptance evidence: private `msp-server-bridge` issues #326 (GitHub→SRV positive read), #342 (both Codex configs, STDIO handshake), #345 (live MCP `tools/call` PASS). First MCP call in #343 failed without a classified root cause; the independent retry succeeded. **Agent discovery boundary:** independent read-only STDIO MCP tools/call is PASS (#345), but a fresh headless `codex exec` session did not expose/select the tool (#352 and #355, TOOL_UNAVAILABLE; no new stock job). The underlying CLI model-tool integration is NOT accepted. No Hermes Gateway session invocation or hot-reload acceptance has been completed.

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

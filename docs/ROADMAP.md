# Roadmap — REMOTE connector first, MCP activation later

## D0 — GitHub source baseline: DONE
- [x] Public `msp-1c-mcp` repository and initial offline-safe connector skeleton.
- [x] Offline test workflow.
- [x] Confirm architecture: diagnostics on existing MSP REMOTE Ubuntu from day one;
      no Hermes integration or active production MCP service during investigation.

## D1 — identify external Windows/1C setup: IN PROGRESS
- [x] User opens a full remote Windows desktop.
- [x] User reports Windows Server 2008 R2 Datacenter; PowerShell version not yet checked.
- [ ] Use a Windows Server 2008 R2 / PowerShell 2.0-compatible read-only probe; do not assume Get-NetIPAddress or [PSCustomObject] exist.
- [ ] Inspect 1C infobase launcher list using a **read-only** command.
- [ ] Determine file-mode/server-mode, actual 1C host and available API publication.
- [ ] Confirm approved route from MSP REMOTE VPS to 1C Windows server.
- [ ] Confirm whether distinct credentials are required for OData/API vs Windows login.

## D2 — establish REMOTE diagnostics: NOT STARTED
- [ ] Deploy restricted diagnostic code in
      `/opt/mcp/projects/msp-1c-mcp/` on REMOTE.
- [ ] Provision least-privilege 1C read-only account; save credentials only
      outside Git at `/opt/mcp/secrets/onec.env` with restricted ownership.
- [ ] Configure approved private encrypted network path to 1C.
- [ ] Add a specific reviewed allowlisted GitHub bridge action (not arbitrary shell).
- [ ] Read OData `$metadata` from REMOTE, return bounded redacted result.
- [ ] Independently verify connectivity, authorization and safe logging.

## D3 — discover and test 1C business operations: NOT STARTED
- [ ] Map actual catalog/document/register field semantics in УНФ.
- [ ] Verify stock reads with 1C UI.
- [ ] Set up an isolated **TEST infobase** and separate test credentials.
- [ ] Test create/read/verify invoice; then posting if applicable.
- [ ] Test create/read/verify shipment; then posting if applicable.
- [ ] Store accepted scripts, validation contracts and synthetic tests in GitHub.

## D4 — activate MCP runtime: FUTURE
- [ ] Reuse the validated REMOTE connector behind MCP tools.
- [ ] Integrate with REMOTE `msp-server-stack` / Hermes after authorization.
- [ ] Add idempotency, approvals, role-based restrictions, independent
      verification and audit before any production writes.

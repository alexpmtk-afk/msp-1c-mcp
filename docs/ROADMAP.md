# Roadmap — REMOTE connector first, MCP activation later

## D0 — GitHub source baseline: DONE
- [x] Public `msp-1c-mcp` repository and initial offline-safe connector skeleton.
- [x] Offline test workflow.
- [x] Confirm architecture: diagnostics on existing MSP REMOTE Ubuntu from day one;
      no Hermes integration or active production MCP service during investigation.

## D1 — identify external Windows/1C setup: IN PROGRESS
- [x] User opens a full remote Windows desktop.
- [x] User reports Windows Server 2008 R2 Datacenter and confirms PowerShell 2.0.
- [x] Confirm PowerShell 2.0 on Windows Server 2008 R2 using `$PSVersionTable.PSVersion`.
- [x] Run one PowerShell 2.0-compatible read-only diagnostic script via a local `.ps1` file to avoid legacy console multiline paste issues.
- [x] Confirm user-level 1C launcher file exists: `%APPDATA%\\1C\\1CEStart\\ibases.v8i` (`Test-Path=True`).
- [x] Read registered UNF infobase entry: **FILE mode** on a local Windows D: volume (exact path deliberately excluded from public Git).
- [x] Confirm registered UNF connection is file-mode, not server-mode.
- [x] Confirm Windows host has 1C 8.3 Server Agent service RUNNING and 8.5 Server Agent service STOPPED; these services do NOT prove that UNF runs in server mode.
- [x] Confirm 1C client and 8.3 server worker processes are present (from PowerShell 2.0 diagnostic script).
- [ ] Determine whether 1C OData/HTTP is published and any web server is installed. The collected service output does not establish a published API.
- [x] Existing Windows RDP connection targets an RFC1918 private 192.168.x.x address (exact address deliberately omitted from public Git).
- [x] User reports connecting to 1C Windows server via standard RDP without manually enabling a VPN; this alone does NOT prove direct LAN access (possible pre-existing route or RD Gateway).
- [ ] Determine actual client-side route / whether RD Gateway is configured, without publishing sensitive IP details.
- [ ] Resolve reported RDP certificate identity warning with the administrator (hostname mismatch and untrusted issuer); do not bypass identity checks as the default.
- [ ] Confirm approved private route from MSP REMOTE VPS to 1C Windows server; connectivity remains UNVERIFIED.
- [ ] Check RD Gateway/client route and identify an administrator-approved secure private networking option; do NOT publicly expose RDP/SMB/WinRM.
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

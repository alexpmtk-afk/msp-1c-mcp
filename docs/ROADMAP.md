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
- [x] Windows client trace to RDP target completes in a single hop (~1 ms); suggests local/on-link or transparent routed connectivity, **not** proof of physical location or direct access from VPS.
- [x] Workstation adapter `Ethernet` has an RFC1918 192.168.x.x address with `/24` prefix; Windows 1C server previously reported a `/26` prefix. Different subnet masks mean reachability may be asymmetric/routed; do not modify networking or presume direct L2. Exact addresses omitted from public repository.
- [x] User requires **24/7 server-side connectivity independent of HOME Windows PC** in production, but explicitly accepts a temporary workstation relay during development.
- [x] Decide provisional path: Windows workstation -> Tailscale host-only subnet route -> REMOTE Ubuntu, per [temporary gateway plan](TEMP_WORKSTATION_GATEWAY.md).
- [x] User checked Windows workstation Tailscale service **Running**, and Tailscale Machines console shows the Windows workstation online (2026-10-12).
- [x] Tailscale web console: both Windows workstation and one Linux VPS online in the same tailnet (2026-10-12).
- [x] Read-only workstation ICMP probe to verified MSP VPS Tailscale IP: **3/3 replies, 0% loss**, 56–497 ms; this proves workstation-to-VPS ICMP only, **not** VPS-to-Windows-server reachability or subnet routing.
- [x] Local Tailscale web interface at Quad100 opened successfully on Windows workstation; device `manager-mp2` shows Connected, `Subnet router` setting visible, session mode `Viewing` (2026-10-12). This is **not** management authorization or a configured subnet route.
- [x] User completed Tailscale identity confirmation in browser (success page, 2026-10-12). This verifies web sign-in, **not yet** that local device UI entered `Managing` mode.
- [x] After Tailscale identity verification, local Quad100 UI no longer displays `Viewing` and shows interactive controls (user screenshot, 2026-10-12). This suggests management UI authorization, but Windows CLI 401 resolution is NOT verified.
- [x] Opened Windows Tailscale local `Subnet router` page (2026-10-12); it reports **Not advertising any routes**, CIDR entry and `Advertise routes` action available, no change performed.
- [x] Inspected Tailscale admin Access controls → Policies (2026-10-12): effective displayed rule is **allow-all**, `src=["*"]`, `dst=["*"]`, `ip=["*"]`. Official wildcard semantics include all approved subnet routes; simply adding a narrower allow rule would NOT limit access. Do not advertise the 1C route yet.
- [x] Read the full default Tailscale policy JSON: single unrestricted grant and default self-device Tailscale SSH `check` rule. User-owned peer inventory is five nodes; tagged/shared dependencies not yet independently audited.
- [x] Prepared a **non-executable, placeholder-only** access-policy proposal in [TAILSCALE_1C_POLICY_PROPOSAL.md](TAILSCALE_1C_POLICY_PROPOSAL.md); preserves user-owned device access and scopes later 1C endpoint to one VPS and validated API port. **NOT APPLIED.**
- [x] User explicitly requested an expedited **temporary pilot without changing the existing allow-all Tailscale policy**; postpone ACL redesign. Warning acknowledged: if route is approved, any authorized tailnet peer matching current broad grant may reach legacy host. Restrict advertised route to **one /32 host**, do not expose the whole LAN. For production, require stricter policy before writes.
- [ ] Advertise only that /32 route via authenticated Windows Tailscale local web UI; approve only that route in Machines console.
- [x] Read-only Windows 10 check on `manager-mp2`: IPv4 `Forwarding=Disabled` on both `Ethernet` and `Tailscale` interfaces (2026-10-12).
- [ ] For temporary pilot only, enable forwarding on precisely these two interfaces in ActiveStore from elevated PowerShell, verify state and keep exact rollback commands. Do not change legacy 1C Windows host.
- [ ] Confirm the advertised /32 route is **Approved** in Tailscale console after the user's Save; Linux VPS route acceptance and independent connectivity test remain pending.
- [ ] Before **any save**, securely back up the currently working tailnet policy outside public Git; inspect existing device tags, shared nodes, approved routes, and required connectivity. Later validate replacement grants with `tests` and preserve a recovery path.
- [ ] Ensure policy tests prevent other peers from reaching the legacy 1C host while the intended MSP VPS can use only required ports. Policy tests are assertions, not deny rules. Verify continuing access to current VPS/Hermes services.
- [ ] Check host Windows IP forwarding (read-only first); official Tailscale subnet router docs require forwarding, then advertise only host-specific route with route approval and policy restrictions.
- [x] Identify actual VPS via read-only private bridge issue #203 (2026-10-08): self node `vm-817589`; matches online machine in current admin console.
- [ ] Resolve Windows Tailscale unattended/server-mode 401 on management CLI without resetting or replacing current device connection.
  - **Additional observation (Windows tray screenshot, 2026-10-12):** Tailscale menu shows `running in server mode (LOCAL SERVICE)` and only Log in, Update, About, Exit; no Preferences menu for current user. This is consistent with lacking ownership of the unattended session or enforced UI policy; no change has been made. Read-only check of local Tailscale `PreferencesMenu`/`UnattendedMode` system policy is the next diagnostic step; do not click Log in or Exit, reset state, or reinstall. Running as elevated Administrator (`True`) did not resolve. Verify owner and available local UI controls first.
  - **Read-only registry check:** `HKLM:\SOFTWARE\Policies\Tailscale` does not exist (`TAILSCALE POLICY: NOT SET`), so no policy was found at that path; the existing unattended/server-mode Tailscale session continues to reject even elevated Windows user with HTTP 401. No Tailscale settings or Windows service state changed.
- [ ] Next, once authorized, advertise and approve **only /32 host route** for the legacy Windows 1C server, with strict tailnet access rules; leave rest of LAN unadvertised.
- [ ] Configure host-only subnet route with local admin permission, approve in tailnet and restrict access (no full LAN or public RDP exposure).
- [ ] Verify approved connectivity from REMOTE to old Windows host without changing the 1C server.
- [ ] Prefer an always-on **network-edge VPN peer** (existing router/firewall if supported) connected securely to MSP Ubuntu VPS; verify who operates the gateway before changes.
- [ ] If no suitable edge VPN peer exists, evaluate a separate authorized always-on gateway or a narrowly-scoped outbound connector on the 1C host only after OS/support and security review.
- [ ] Do not install current Tailscale on Windows Server 2008 R2 (unsupported OS); do not expose legacy Windows RDP/SMB/WinRM to Internet.
- [ ] For **production**, migrate the pilot gateway to an approved always-on site peer; workstation must not remain a dependency.
- [ ] Resolve reported RDP certificate identity warning with the administrator (hostname mismatch and untrusted issuer); do not bypass identity checks as the default.
- [ ] Confirm approved private route from MSP REMOTE VPS to 1C Windows server; connectivity remains UNVERIFIED.
- [ ] Check RD Gateway/client route and identify an administrator-approved secure private networking option; do NOT publicly expose RDP/SMB/WinRM.
- [ ] Confirm whether distinct credentials are required for OData/API vs Windows login.

## Temporary network pilot — 2026-10-12
- [x] User restored workstation Internet after **disabling** IPv4 Forwarding on Ethernet and Tailscale; normal browsing works again. Do not re-enable host IP forwarding or use workstation as Windows subnet router for this project.
- [x] Workstation includes Windows OpenSSH client; read-only TCP test to current VPS Tailscale address port 22 returned **True**. This proves network-level TCP reachability, not SSH login.
- [ ] Validate a **non-mutating authenticated SSH handshake** from workstation to MSP VPS with host-key checking; credentials must remain outside GitHub/chat.
- [ ] Evaluate a narrowly scoped **reverse SSH port forwarding** only after an authorized 1C HTTP/OData endpoint and actual TCP port are verified. It must not change workstation routes, DNS or packet forwarding.
- [ ] Remove the previously advertised and approved /32 Tailscale subnet route after ensuring it is not used; broad tailnet allow-all policy remains unchanged and must not be treated as protection of this route.

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

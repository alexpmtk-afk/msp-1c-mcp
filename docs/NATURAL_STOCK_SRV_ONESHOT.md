# NewBase natural stock schema — separate LocalService one-shot

Status: REVIEWED/OFFLINE CI PASS, NOT EXECUTED ON PHYSICAL SRV.

## Administrative boundary

The installed MspOnecHttpsAgentSystem on SRV (Windows Server 2008 R2 /
PowerShell 2.0) accepts only fixed pre-approved queue operations. The GitHub/VPS
bridge cannot execute a new SRV PowerShell command. Do not weaken this
allowlist. SRV\parshin remains non-administrator.

These scripts let an already-authorized Windows administrator run a separate
manual-only one-shot task as LocalService (S-1-5-19) without changing or
restarting the existing scheduled agent, IIS, Hermes or 1C. No automatic
triggers are configured on the separate task.

## Immutable source snapshot

GitHub source commit: 3909889c4aa177d834961d26d13af6541a20f3d4
Source directory: scripts/windows/

- onec-natural-stock-schema-preflight.ps1 — git blob c82e433205ee3a8353165381c33a7a2f43892b50
- onec-natural-stock-schema-runner.ps1 — git blob 079e7fe7760cd9a209c5973f91a3c5c75b87d6e3
- onec-natural-stock-schema-once.ps1 — guarded administrator one-shot installer

Reviewed files are staged in the administrator's:

  %TEMP%\OnecNaturalSchema_20261015\

Existing portable curl on SRV (used for prior 1C agent deployments) may
download the three files from this immutable base URL:

  https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/3909889c4aa177d834961d26d13af6541a20f3d4/scripts/windows/

Once the THREE scripts are staged, in an **already elevated and authorized**
PowerShell 2 session on SRV, execute this fixed one-time procedure:

    $f=Join-Path $env:TEMP 'OnecNaturalSchema_20261015\onec-natural-stock-schema-once.ps1'; & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $f -ExpectedComputerName 'SRV'

The installer verifies pinned blob hashes of helper and runner, existing
system task status, credential presence, real LocalService identity, and
PS2 source syntax. It copies only these two fixed helpers into the existing
ProgramData agent bin, registers the separate zero-trigger task, starts it
once and checks a sanitized bounded report in agent state.

No raw product/client records, GUIDs or credentials are exported. The
one-shot task is deleted after the report; on failures it fails closed.
Files and status may remain for administrator inspection.

## Acceptance and remaining work

Expected fields: ARTICLE_FIELD_PRESENT, CODE_FIELD_PRESENT, NAME_FIELD,
candidate warehouses, EXAMPLE_ARTICLE_MATCHES, EXAMPLE_CODE_MATCHES.
Code is the internal 1C catalog code; it must not be assumed to equal the
user's normal article (e.g. трн.02.034.9005.02.30).

A successful one-shot proves ONLY the metadata read, not working natural
stock lookup. If no authorized administrator can run the script, mark
BLOCKED_ADMINISTRATIVE_SRV_EXECUTION; do not bypass LocalService controls.

After a verified schema, expand allowlisted VPS queue/SRV agent with a
fixed Unicode-safe lookup supporting article OR product name, optional
real warehouse name or complete all-warehouse totals, then accept via
native Hermes agent and a real Telegram inbound turn. Preserve the
existing read-only GUID tool throughout.

# Server-owned 1C HTTPS agent: staged LocalService migration

Status: DESIGN + READ-ONLY PREFLIGHT. Nothing in this change installs/reconfigures
a Windows task, opens inbound ports, accesses 1C, or changes passwords.

## Goal

Replace the personal Windows Task Scheduler installation under the original
operator account with an **independent server-owned polling process**, without
requiring an interactive session, employee identity or employee password.

Use Windows Server 2008 R2 built-in `NT AUTHORITY\LOCAL SERVICE` (SID S-1-5-19).
Prefer a fixed native Task Scheduler 2.0 COM task configured for
`TASK_LOGON_SERVICE_ACCOUNT=5`, non-elevated `TASK_RUNLEVEL_LUA=0`;
no account password. This is a system-account scheduled process, **not** an
SCM Windows Service. Do not attempt to register a bare PowerShell process as a
traditional Windows service.

## Files and access controls (proposed, not yet installed)

- `%ProgramData%\MspOnecAgent\bin`: reviewed PowerShell scripts, trusted
  portable curl executable and CA bundle; admin/SYSTEM write, LocalService read
  and execute; neither normal users nor LocalService may modify code.
- `%ProgramData%\MspOnecAgent\config`: pinned HTTPS 8443 endpoint; admin
  write only, LocalService read.
- `%ProgramData%\MspOnecAgent\secrets`: a new agent token encrypted using
  Windows DPAPI **LocalMachine scope**, file ACL limited to SYSTEM,
  Administrators and LocalService. Machine scope DPAPI alone is **not sufficient**:
  only file ACLs and code-write restrictions keep it private.
- `%ProgramData%\MspOnecAgent\state`: only dedicated LocalService plus
  Administrators/SYSTEM may read/write; sanitized status, bounded logs and
  ACK-retry/replay markers.

Use well-known SIDs rather than localized names for ACLs. Provision secrets
locally using hidden input, never in GitHub, chat, scripts, process command
arguments or logs. If possible, provision a *second distinct* agent token
on the VPS and accept both only during migration; this permits verified source
separation and clean revocation of the old personal token after cutover.

## Safety gates

1. Read-only PS2 preflight on real SRV: machine version, LocalService SID,
   availability of machine-scope DPAPI and Task Scheduler 2.0, whether the
   current process can perform the required administrative installation.
   This can be run under an unprivileged account.
2. Implement and Windows-CI-review a fixed LocalService-only poller and
   native task-registration script, plus per-component ACL verification and
   rollback. Do not alter the existing user task in this step.
3. With authorized Windows administrator, install alongside the old task but
   **do not let two agents consume test jobs indistinguishably**. Require an
   identifiable new agent proof or temporarily pause the old poller for a
   controlled test; provide immediate restoration on failure.
4. From GitHub issue command, verify the new agent processes an ID-matched probe
   while no user is signed into SRV. Check permissions and diagnostics without
   returning credentials. Test a scheduled run, RDP logout and authorized
   reboot only if explicitly approved by the server owner.
5. Disable/remove the user-specific task; rotate/revoke the old agent token
   and securely retire user-scoped DPAPI enrollment **only after** an accepted
   new system-agent round trip. Do not delete current state prematurely.
6. In later independent review, add **GET-only** OData operations pinned to
   the TEST infobase `NewBase`; keep write operations disabled and verify
   true read-only 1C authorization. Do not expose 1C IIS publicly.

## Diagnostics

The future agent should report its installed version, alive / last
successful poll, UTC timestamps, last sanitized error code, recent task ID,
ACK status and age of its last run. Keep logs bounded and ACL-restricted.
Never return raw OData payloads, bearer tokens, Windows usernames, file
system secrets or arbitrary PowerShell outputs as diagnostics.

## Rollback

Stop or remove *only* the newly introduced LocalService task and its
dedicated files after stopping the process; preserve the old user poller
and prior VPS token until independent acceptance. No IIS, Hermes, nginx,
Tailscale, GitHub runner, production 1C, or unrelated task modifications.

A **PASS from GitHub PowerShell parser is not an actual PS2/LocalService
runtime acceptance**. The target Windows 2008 R2 environment must prove this.

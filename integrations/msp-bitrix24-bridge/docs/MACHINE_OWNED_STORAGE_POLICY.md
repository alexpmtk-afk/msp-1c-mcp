# Machine-owned SRV runtime policy — 2026-10-15

**User-confirmed non-negotiable requirement:** All software, databases,
scheduled tasks and long-lived dependencies run as server-owned resources,
not as installations belonging to a named interactive/RDP user.
Logging off, switching users or rebooting MUST NOT interrupt the
autonomous collection pipeline after boot.

## Canonical locations

- Bridge root: `C:\ProgramData\MspBitrix24Bridge\`
- SQLite runtime: `C:\ProgramData\MspBitrix24Bridge\bin\sqlite3.exe`
  or a tested machine-wide provider in a service-accessible folder.
- Local DB: `C:\ProgramData\MspBitrix24Bridge\data\customers.db`
- Change queue and checkpoints: tables in the same machine-owned DB.
- Logs: `C:\ProgramData\MspBitrix24Bridge\logs\`
- Secrets: isolated access-controlled server-side secret storage,
  never in user profile or the main DB plaintext.
- Trusted HTTPS clients and CA chain: dedicated machine-owned
  runtime location (not `C:\Users\parshin\Desktop\OnecHttpsPortable_20261013_095710`).
  That user folder is only a temporary manual bootstrap source today,
  NOT a runtime dependency.
- Prefer dedicated `staging\` under the machine-owned root with
  explicitly ACLed service ownership; never `%LOCALAPPDATA%`,
  `%APPDATA%`, `%USERPROFILE%`, or named users' desktop folders.

## Process ownership & startup

- Process identity: `NT AUTHORITY\LOCAL SERVICE` (`S-1-5-19`),
  as already used by the `MspBitrix24Bridge` task.
- Startup independent of interactive logon via machine-owned Windows
  Scheduled Task startup trigger (or an approved service).
- No user-specific login task, desktop startup shortcut or RDP session.
- Single owner/writer of SQLite local state. Grant only required
  read/execute permissions on binaries and modify permissions
  on the specific `data\`, `logs\`, `staging\` directories.
- An administrator/approved service installer must configure ACLs
  once; `SRV\parshin` need not and must not be granted local admin
  or be added to the Administrators group.
- Secure DB and backup paths against unauthorised readers; SQLite
  does not encrypt data at rest by default.
- On reboot, service restarts safely using idempotent checkpointing.
  Queue contents must survive RDP logoff and restart.
- Installation must leave existing `MspOnecHttpsAgentSystem`,
  IIS 1C publication and other business services unchanged.
  No implicit or automatic sync enablement: `SAFE_IDLE` remains.

## Explicit correction to prior pilot

The earlier `bin/pilot-create-sqlite-store.ps1` targeted
`%LOCALAPPDATA%\MspCustomerStorePilot`. This was inconsistent with
the machine-owned runtime requirement. **DO NOT RUN** the previous
command, even though its historical commit remains addressable.
The script at the latest branch head is deliberately changed to
immediately refuse execution, with no changes or downloads.

The next SQLite acceptance script must target only a preapproved,
ACL-protected machine-owned path. Before any install, verify the
operating system/SQLite binary, service task identity and writable
directory permissions for LOCAL SERVICE. An admin or previously
authorized service installation process performs machine-wide
staging; do not stage under a personal profile as a workaround.

## Acceptance

1. DB created under ProgramData with intended ACLs; no SQLite app
   in any user profile.
2. Machine-owned task/service runs as LOCAL SERVICE with boot trigger.
3. Empty DB schema, read/write transaction and rollback PASS under
   LOCAL SERVICE, *not merely* under an interactive administrator.
4. Logout of RDP and restart of SRV do not prevent reading/writing.
5. Final initial customer load and subsequent 1C change-registration
   ingestion both use the same protected machine-owned DB.
6. Bitrix24 remains out of scope until the standalone SRV system
   is accepted.

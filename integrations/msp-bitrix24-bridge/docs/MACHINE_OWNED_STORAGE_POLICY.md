# Machine-owned SRV runtime policy — 2026-10-15

**User-confirmed non-negotiable requirement:** All software, databases,
scheduled tasks and long-lived dependencies run as server-owned resources,
not as installations belonging to a named interactive/RDP user.
Logging off, switching users or rebooting MUST NOT interrupt the
autonomous collection pipeline after boot.

## Updated architecture: independent SRV customer collector (2026-10-15)

The user's first priority is an autonomous **1C -> SRV local database**
pipeline; Bitrix is LAST. To keep collection independent of the
existing Bitrix24 SAFE_IDLE bridge, the standalone collector gets its
**own machine-owned root**:

| Part | Canonical server-only path or identity |
| --- | --- |
| Collector root | `C:\ProgramData\MspCustomerStore\` |
| 1C ingestion/refresh runner | `C:\ProgramData\MspCustomerStore\bin\collector.ps1` |
| SQLite executable/provider | `C:\ProgramData\MspCustomerStore\bin\` |
| HTTPS client | `C:\ProgramData\MspCustomerStore\bin\curl.exe` if used |
| TLS CA bundle | `C:\ProgramData\MspCustomerStore\config\curl-ca-bundle.crt` |
| SQLite main database and durable inbox/checkpoints | `C:\ProgramData\MspCustomerStore\data\customers.db` |
| Configuration | `C:\ProgramData\MspCustomerStore\config\` |
| Protected secrets | `C:\ProgramData\MspCustomerStore\secrets\` |
| Logs | `C:\ProgramData\MspCustomerStore\logs\` |
| Controlled temporary/staging files | `C:\ProgramData\MspCustomerStore\staging\` |
| Machine-owned backups | `C:\ProgramData\MspCustomerStore\backups\` or a separately ACL-protected server backup target |
| Service identity | `NT AUTHORITY\LOCAL SERVICE` (`S-1-5-19`) |
| Independent startup task (planned) | `MspCustomerStoreSync`, Windows boot trigger |

The **preexisting** `C:\ProgramData\MspBitrix24Bridge\`
remains separate and unchanged. Its `MspBitrix24Bridge` scheduled
task stays `SAFE_IDLE`. Older documents referring to
`C:\ProgramData\MspBitrix24Bridge\data\customers.db`
are superseded as collector-path proposals; NO existing files are moved.

All persistent components, executables, providers, certificates,
configuration, secrets, queues, database, logs, backups, and tasks
are machine-owned. No runtime dependency on an interactive user's
profile, login, desktop, credentials or RDP session.
Manual bootstrap via a user's shell is allowed only for staging
read-only diagnostics; nothing in the **running** chain may depend
on that profile. Local Service permissions are verified with
actual service-context tests before enabling any scheduled ingestion.

## Original bridge locations (existing, unchanged)

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

## S3 first gate: machine-owned OData credentials under LOCAL SERVICE

After the successful S2 empty SQLite acceptance, S3 must read TEST 1C
through the independent machine-owned collector, not through a user
logon session.

Bootstrap requires one SRV-local password entry only for
`MCP_OData_ReadOnly` using `Read-Host -AsSecureString`.
The password is stored only as a Windows DPAPI `LocalMachine`
ciphertext blob in
`C:\ProgramData\MspCustomerStore\secrets\onec-test-odata.dpapi`.
No plaintext/password on command line, in GitHub, logs or files.

**Security warning:** machine-scope DPAPI is NOT bound only to LOCAL SERVICE:
other processes on the same computer that can read the encrypted file can
decrypt it. Restrictive NTFS ACLs (SYSTEM, Administrators, LOCAL SERVICE only)
are mandatory. The service account needs read access; the file must not
be made available through IIS, SMB or user profiles. For stronger per-identity
protection, redesign around service-owned CurrentUser DPAPI later.

`bin/provision-onec-service-credential.ps1` stages a checksum-pinned
read-only proof script and provisions the encrypted blob with no replacement
of an existing secret. A no-trigger, manually invoked
`MspCustomerStoreCredentialProof` task executes under LOCAL SERVICE,
decrypts DPAPI there, GETs only an aggregate buyer count from local
TEST 1C OData and writes a count/status marker in machine-owned
`state`. On PASS, the temporary proof task is deleted.
Existing `MspCustomerStoreSync` remains boot-off / SAFE_IDLE.
No customer cards yet imported, no 1C writes, no Bitrix calls.
Stop on any FAIL; do not rerun blindly because the encrypted blob may remain.

## Verified LF/CRLF mismatch and offline schema-only resume

Physical SRV failed with `SOURCE_SHA256_MISMATCH` after
`SQLITE_VERSION=3.43.2`. Investigation: raw GitHub LF SQLite schema hash
`50748aada5273f60a8056cb1358334cf3fe3c221b67ca8766c8d18a9003b30a3`;
Windows checkout CRLF schema hash
`309b0bcfb0487369dc6d6a5d9bf639b90a2b36f65de2e1738ea0e440a622e958`.
Mistake: installer pinned checkout hash, not downloaded LF hash.

Smoke script and INI manifest hashes were already correct. Previous
operation should have downloaded/staged them and copied them into the
machine-owned tree, then downloaded the SQL to staging, failing on hash.
New `bin/resume-machine-customer-store-from-schema.ps1` verifies
that EXACT partial state, hashes, no unexpected files/tasks, service ACLs,
and existing SQLite runtime. No network downloads or deletion.
Copies only the already staged, LF SHA-256 verified SQL schema and
then creates an on-demand service task with disabled boot trigger and
tests empty SQLite DB as LOCAL SERVICE. If unexpected, fail closed.
No 1C, Bitrix or existing bridge changes; never auto-retry.

## Recovery checkpoint: ZIP already verified on physical SRV

Observed `CURL_SYSTEM_VERSION=PASS`, `CURL_SYSTEM_HASH=PASS`,
`SQLITE_ARCHIVE_SHA256=PASS`, followed by
`GATE=SQLITE_ENTRY_MISSING` in `SQLITE_EXTRACT`.
Likely archive nesting; Shell.Application root `ParseName('sqlite3.exe')`
does not traverse ZIP subfolders. This is a hypothesis until on-SRV
inspection confirms the archive layout.

**Do not rerun the earlier resume script.** Use only the stage-specific
`bin/resume-machine-customer-store-from-zip.ps1` after CI acceptance.
It accepts precisely one extra existing staged ZIP, rehashes the exact
official file and searches both the root and one nested ZIP folder
for `sqlite3.exe` using Shell.Application. Does not fetch ZIP again.
If the entry remains absent, it prints the ZIP root entry names, then
fails closed; no other files or tasks are changed in this stage.
All other preconditions and LOCAL SERVICE empty-smoke requirements
are retained. No Bitrix, OData, other system task changes.
Do not auto-retry a failed stage-specific resume.

## 15 Oct 2026: curl version flag failure and safe resume

Machine-owned runtime inventory and ACL diagnostic confirmed that the root
and nine directories exist, appropriate ACLs are in place, curl.exe and
CA bundle were copied with matching SHA-256, no DLLs are needed,
while SQLite ZIP, executable, DB and collector scheduled task are absent.

**Root cause**: installer invoked `curl -version` (invalid curl option
syntax), which produced stderr and a PowerShell `RemoteException`.
Correct check is `curl --version`. The partial install needs NO deletion.

The resumed script `bin/resume-machine-customer-store.ps1` requires
an exact partially installed state and must run only once after pinning
GitHub SHA256. It uses the machine-owned curl.exe and CA to obtain
SQLite 3.43.2 and pinned scripts, then registers an on-demand
`MspCustomerStoreSync` task under LOCAL SERVICE with DISABLED boot
trigger. A manual service smoke creates an empty SQLite DB, verifies
four tables, a synthetic transaction rollback, and back-reads zero
customer rows. No 1C, no Bitrix calls. Changes to any other task
are prohibited. Do not retry after any partial failure without another
read-only inspection.

# SRV-first customer collection — execution order (2026-10-15)

**Current priority**: Build an autonomous complete source→local store pipeline
on **physical SRV** before any Bitrix24 API calls, portal deployments or UX.
User chose **Option B**: change registration inside 1C rather than periodic
full scans.

## Acceptance gates — one block/test/report at a time

| Gate | Objective | Current |
| --- | --- | --- |
| S0 | Test 1C read-only inventory, all 6,433 active buyers and category split | PASS |
| S1 | Read-only SRV runtime/provider + 1C exchange plan metadata preflight | PASS; OData published one equipment exchange plan; no customer delta feed confirmed |
| S2 | SQLite executable compatibility, empty DB, transactional write/read/rollback in user-isolated staging | SCRIPT READY; NOT RUN (system-owned protected DB pending) |
| S3 | One-time initial load of ALL buyer types into local DB; 6,433 unique GUIDs; hash/count/back-read PASS | NOT STARTED |
| S4 | Change source: isolated 1C TEST change registration + minimal durable extraction endpoint, with developer authorization | NOT STARTED |
| S5 | Full automatic test: edit TEST buyer → registration → local refresh, reboot/resume, duplicate suppression | NOT STARTED |
| S6 | Only after S0-S5: connect Bitrix24 application, lookup and/or sync | OUT OF SCOPE NOW |

## Inventory facts, SRV, 2026-10-15

Read-only S1 accepted: `METADATA_ENTITY_SETS=1492`;
`EXCHANGE_PLAN_ENTITY_SETS=1`; published
`ExchangePlan_ОбменСПодключаемымОборудованиемOffline`.
This is unrelated to the planned customer sync. Do not repurpose it.
Unpublished 1C exchange plans may also exist, so published OData
metadata is not a complete configurator inventory.
`PLAN_CHANGE_EVENTS_ACCESS=NOT_YET_VERIFIED`, `DATA_WRITES=NO`,
`FILES_CREATED=NO`, `RESULT=PASS;STAGE=SRV_CUSTOMER_PIPELINE_PREFLIGHT`.

**SQLite runtime inventory (SRV, PASS)**:
Windows Server 2008 R2 SP1 version 6.1.7601, x64; native PowerShell 2.0,
CLR 2.0.50727.5420; .NET 2.0 present; .NET 4 Full registry present;
.NET 3.5 registry not found. C: free 60.37 GiB. No SQLite CLI/provider,
no `customers.db`; `SAFE_IDLE=YES`.

**Correction, 15 Oct 2026:** The earlier user-local SQLite pilot
(`%LOCALAPPDATA%\MspCustomerStorePilot`) is **CANCELLED**.
Its script `bin/pilot-create-sqlite-store.ps1` is retired and
fails closed at the current branch head. Do not run the previously
provided hash-pinned command. Do not install SQLite into any
specific user's profile.

The next acceptance must install/test SQLite under
`C:\ProgramData\MspBitrix24Bridge\` as a machine-owned
installation and verify its read/write permissions **as**
`NT AUTHORITY\LOCAL SERVICE`. System-owned runtime dependencies
(including HTTPS client and CA) must likewise not depend on
`C:\Users\parshin\`. An authorized administrator or existing
machine-owned bootstrap must grant precise ACLs; `SRV\parshin`
remains a nonadmin user.

See [MACHINE_OWNED_STORAGE_POLICY.md](MACHINE_OWNED_STORAGE_POLICY.md).
Prepare secure SRV service preflight + machine-owned install only,
then perform empty-schema transaction and back-read under LOCAL SERVICE.


Official System.Data.SQLite has historic .NET Framework 2.0/3.5 builds,
but several older package releases are deprecated/unsupported. Do not
install arbitrary binaries on legacy SRV without verifying compatibility
and cryptographic checksums.

## Important 1C platform gate

Native exchange-plan change-registration registers insert/update/delete
events per configured exchange node. It is not proven accessible through
our current read-only OData Catalog GET. In conventional standard OData,
`SelectChanges` for exchange plans may use HTTP POST; this is not covered
by current GET-only privileges. **Do not call POST or create exchange nodes
without explicit 1C test-base authorization and rollback plan**.
Current onec access is `MCP_OData_ReadOnly` and works for GET on
local TEST port 8085; do not touch production or the other system agent.

Source: https://its.1c.ru/db/content/metod8dev/src/developers/platform/metod/dataexchange/i8102276.htm
Standard OData: https://github.com/hacker-cb/1c-odata/blob/master/docs/1c/markdown/17.4_-_C%D1%82%D0%B0%D0%BD%D0%B4%D0%B0%D1%80%D1%82%D0%BD%D1%8B%D0%B9_%D0%B8%D0%BD%D1%82%D0%B5%D1%80%D1%84%D0%B5%D0%B9%D1%81_OData_8_3_27.md

## Standalone, system-owned collector directory

Collector is independent of the existing `MspBitrix24Bridge` SAFE_IDLE
task. Target root `C:\ProgramData\MspCustomerStore\`, with separate
boot-start `MspCustomerStoreSync` under `NT AUTHORITY\LOCAL SERVICE`,
plus dedicated `bin`, `config`, `data`, `state`, `logs`,
`staging`, `secrets` and `backups` directories.
No user profile, RDP session, interactive startup or user-scoped curl/CA
path in the working chain. Existing Bitrix and 1C tasks untouched.

Next: execute read-only `bin/audit-machine-owned-customer-chain.ps1`
on SRV to confirm task identity, boot trigger, root access and missing
dependencies. Then develop a tightly scoped machine-owned installer
and empty SQLite transaction verified **as LOCAL SERVICE**.
Admin-level ACL/task provisioning must use an explicitly authorized
installer; do not grant admin rights to `SRV\parshin`.

## Database

Preferred on-SRV format: SQLite, subject to legacy server support.
Proposed path `C:\ProgramData\MspCustomerStore\data\customers.db`.
An **empty schema** is defined in `schema/customer-store.sql`, but has
NOT been installed. Needs physical SRV runtime/provided SQLite CLI or
.NET provider compatibility verification and locked-down ACLs and at-rest
encryption review. Never make customer data files public in GitHub.
JSON permitted for small event messages, not for full mutable directory.
No automatically enabled task until all acceptance gates complete.

Current `MspBitrix24Bridge` task remains `SAFE_IDLE`.
Do not change `MspOnecHttpsAgentSystem` or existing 1C publication.

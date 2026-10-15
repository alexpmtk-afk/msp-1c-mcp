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

Next run `bin/pilot-create-sqlite-store.ps1`, a user-local **isolated
compatibility pilot**, NOT the permanent SRV service database:
`%LOCALAPPDATA%\MspCustomerStorePilot\customers.db`.
It downloads the *official SQLite* x86 3.43.2 ZIP only from sqlite.org,
checks independently published ZIP SHA-256, extracts sqlite3.exe, runs
its version, then downloads the commit-pinned SQL schema and verifies
its GitHub Actions SHA-256 supplied via `-ExpectedSchemaSha256`.
The pilot creates an EMPTY customer DB with four tables, tests
integrity, a synthetic transaction and rollback; it MUST remain empty.
Do not retry blindly if the pilot directory already exists.
No change to system task, live DB, 1C, Bitrix or protected ACLs.
Source for known Win7/Server 2008 shell behavior:
https://sqlite.org/forum/forumpost/1b2892bca0
Checksum cross-check: https://community.chocolatey.org/packages/SQLite/3.43.2

If that is PASS, next promote verified runtime to an ACL-protected
machine-owned SRV path, with proper single-writer policy, encryption
assessment and a separate explicit authorized system deployment.
Then run initial full buyer ingestion.

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

## Database

Preferred on-SRV format: SQLite, subject to legacy server support.
Proposed path `C:\ProgramData\MspBitrix24Bridge\data\customers.db`.
An **empty schema** is defined in `schema/customer-store.sql`, but has
NOT been installed. Needs physical SRV runtime/provided SQLite CLI or
.NET provider compatibility verification and locked-down ACLs and at-rest
encryption review. Never make customer data files public in GitHub.
JSON permitted for small event messages, not for full mutable directory.
No automatically enabled task until all acceptance gates complete.

Current `MspBitrix24Bridge` task remains `SAFE_IDLE`.
Do not change `MspOnecHttpsAgentSystem` or existing 1C publication.

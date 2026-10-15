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
| S2 | Create minimal protected transactional local storage on SRV, verify read/write/reopen under restricted service identity | NOT STARTED |
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

**SQLite compatibility is NOT verified yet**: S1 output supplied did
not include CLI/provider presence, architecture, or .NET runtime lines.
Run the targeted, credentials-free read-only `bin/inventory-srv-sqlite-runtime.ps1`
for the exact environment before attempting any install or writing files.

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

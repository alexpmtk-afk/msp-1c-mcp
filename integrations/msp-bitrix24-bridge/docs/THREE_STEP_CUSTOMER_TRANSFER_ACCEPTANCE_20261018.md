# 1C TEST NewBase → SRV SQLite → Bitrix24: three-task acceptance plan (18 October 2026)

**Primary user goal:** All active buyers visible in Bitrix24, with names, INN, telephone numbers, and an ongoing safe daily refresh for newly created or modified customers. Keep 1C production unchanged. Business data and credentials remain on physical SRV.

## Canonical structure

- Source: 1C TEST database `D:\DATA\NewBase`, read-only OData at loopback 127.0.0.1:8085.
- Local durable DB: `C:\ProgramData\MspCustomerStore\data\customers.db`.
- Transfer: SRV's LocalService worker sends authorized Bitrix24 calls. Bitrix24 does not directly access the SQLite file.
- Stable identity: `(source=MSP_ONEC_NEWBASE, source_guid, CRM entity type)`; no matching on customer name/INN alone.
- Buyer type: 1,941 LEGAL companies, 4,486 PERSON contacts, 6 REVIEW (source snapshot count as of initial import). Never silently drop REVIEW records.
- Data: names/FIO, INN as Bitrix requisites, verified phone values in the native phone field; preserve source values and record field-level differences, do not silently call mismatches synchronized.
- Automatic changes only after initial import completion and field-method acceptance. No recurring mode during V4 initial import.

## Task 1 — Complete and reconcile initial 6,433

Existing `MspNewBaseInitialImportV4` is single-run, no triggers. The latest user-provided result was
`STATUS=RUNNING;MAPPED=1195;TARGET=6433;FIELDS_REVIEW=540;TASK_STATE=4`, with a subsequently queried local database count of `MAPPED=1196;INFLIGHT=9;FIELDS_REVIEW=541;NAMES_REVIEW=36`.
**Do not assume the current count or completion.** Get a fresh read-only SRV receipt.

Acceptance: `MAPPED=SOURCE_ACTIVE`, no unresolved inflight, no missed active customers, no duplicate CRM origin matches, positive full Bitrix count/backread. Keep field-review items explicitly open. If V4 hits the six-hour task limit, resume from durable local map with an inspected, fail-closed continuation; never replay uncertain adds.

## Task 2 — Field completeness and correctness

Current `customer-store.sql` and `refresh-newbase-source-v2.ps1` include `name_short,name_full,person_name,inn`, **not phone**. The existing project review confirms TEST OData exposes a `Catalog_Контрагенты_КонтактнаяИнформация` table part (`docs/NATIVE_BUYER_CHANGE_TRIGGER_S4_V2.md`); its exact columns, type codes, linkage and meaningful phone contents have NOT yet been verified. Inspect real TEST OData metadata and read-only aggregates before implementing the phone extraction. Do not invent `Catalog_Контрагенты.Phone` or assume phone storage and ownership. Add nullable phone fields in a migration with database backup and backread acceptance. Use only confirmed 1C phone values.

Existing initial import puts INN in comments. Confirm CRM requisites and preset, use `crm.requisite.list/add/update` with readback to map real INN and legal full name. Use Bitrix24 `fm` native phone fields with readback. Protect pre-existing user-entered values: define ownership and conflict handling, do not overwrite unrelated data. Ensure names/field review queues reach an understood final state. At minimum test examples of each LEGAL, PERSON, and REVIEW.

## Task 3 — Daily ongoing changes (not a second initial import)

The existing `refresh-newbase-source-v2.ps1` has full-source scan and local `msp_auto_outbox` detection, but the existing `pump-newbase-bitrix-batch-v2.ps1` only creates new entities; it marks existing ones `UPDATE_REQUIRED` rather than applying source changes. A separate `update-newbase-existing-once-v1.ps1` is already implemented and offline-tested for ONE existing GUID with optional explicitly approved update of CRM item and company requisite; it is NOT installed, bulk-accepted or automation-ready (`docs/ONE_BUYER_UPDATE_ACCEPTANCE_V1.md`). Reuse its tested identity/ownership/backread conditions rather than inventing a competing update path. `msp-newbase-auto-tick-v2.ps1` can rescan each 15 minutes and is not equivalent to a single morning run. Do **not** enable `install-newbase-auto-v2.ps1` without repair and validation.

Use one daily time, e.g. 08:30 SRV local, to read complete active 1C buyers, atomically refresh durable SQLite, compare by GUID/fields, and enqueue only NEW/CHANGED. Existing Bitrix CRM cards are updated by ID, new GUIDs created once. Keep per-record confirmed state; survive network errors and resume without duplicates; distinguish REMOVED / disabled without automatic destructive CRM deletion. Update target phone/requisite fields only after ownership checks.

Acceptance: a new synthetic TEST 1C buyer is present in SQLite and CRM after a single daily cycle, a changed customer updates the same CRM ID, unchanged records generate no CRM writes, interruption can be safely replayed, 1C production untouched, no secrets/PII printed. Activate the recurring task **only after all acceptance tests**, with user confirmation of schedule and operational access.

## Status format at each task

Report exactly: **Completed**, **Not completed / blockers**, **Evidence**, **Next action**.
No task is declared complete merely because a GitHub test passed or a Windows task was started.

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

Existing `MspNewBaseInitialImportV4` is single-run, no triggers. User-provided later final V4 observation: `TASK_STATE=3`, status reports `ERROR_ID=NEWBASE_CURL_FAILED;MAPPED=5245;TARGET=6433`; independent SQLite read `SOURCE_ACTIVE=6433;MAPPED=5245;INFLIGHT=0;GAPS=1188;FIELDS_REVIEW=1867;NAMES_REVIEW=105`. Thus V4 stopped, not complete. V5 worker and guarded one-time launcher are being prepared; V5 must not be reported deployed until real SRV receipts confirm.
**Do not assume the current count or completion.** Get a fresh read-only SRV receipt.

Acceptance: `MAPPED=SOURCE_ACTIVE`, no unresolved inflight, no missed active customers, no duplicate CRM origin matches, positive full Bitrix count/backread. Keep field-review items explicitly open. If V4 hits the six-hour task limit, resume from durable local map with an inspected, fail-closed continuation; never replay uncertain adds.

## Task 1 — Actual SRV acceptance, 18 October 2026

User-provided V5 completion receipt: `STATUS=PASS_WITH_FIELD_REVIEW;MAPPED=6433;TARGET=6433;FIELDS_REVIEW=2254;NAMES_REVIEW=123;SOURCE=TEST_NEWBASE;AUTO_UPDATE=OFF;ONEC_WRITES=0`. Task Scheduler: `TASK_STATE=3;TASK_LAST_RESULT=0`. Separate read-only SQLite acceptance: `SOURCE_ACTIVE=6433;MAPPED=6433;INFLIGHT=0;GAPS=0;UNIQUE_CRM=6433`. This proves completion of the local confirmed map and no duplicate CRM IDs in the local map. Full independent live Bitrix re-enumeration has not yet been performed. Existing field-review queue remains.

## Task 2 — Field completeness and correctness

The GET-only v1 schema probe was executed on physical SRV; source GET succeeded but its metadata parser failed: `STATUS=FAIL;PHASE=PARSE_CONTACTINFO_METADATA;GATE=RUNTIME_ERROR`, without exporting customers or calling Bitrix24. This is **not** a phone/source-data error. New v2 parser supports OData tabular-part metadata declared either as EntitySet or as NavigationProperty, and records a sanitized exception type and line on a continued parse failure. Native Windows synthetic XML tests and CI passed. V2 actually ran on SRV and failed on PowerShell 2.0/CLR2: `STATUS=FAIL;PHASE=PARSE_CONTACTINFO_METADATA;GATE=RUNTIME_ERROR;EXCEPTION_TYPE=RuntimeException;ERROR_ID=TypeNotFound;ERROR_LINE=42`. Its exact source line 42 uses `XmlReaderSettings.DtdProcessing=[Xml.DtdProcessing]::Prohibit`, an API available only in .NET 4.0+. V3 replaces it with .NET2-compatible `XmlReaderSettings.ProhibitDtd=$true`, uses fully qualified XML types, and reports sanitized parse errors. V3 native Windows synthetic XML tests and static safety CI PASS: `bin/probe-newbase-contactinfo-metadata-readonly-v3.ps1` (worker sha256 `9dfd2a10cf67e91cb23ecfcfa5420d8f21ac1f58fcdbaa1d1d3e82f4e8c96040`), with guarded launcher `bin/start-newbase-contactinfo-metadata-readonly-v3.ps1` (launcher sha256 `18fed10b943664d79b0084ffcb416d9d4e54e1b5c0e33fb54c25499a8ada74da`). Real PS2 execution of V3 is NOT yet confirmed. This is still a schema-only GET with no customer rows/phone exports or CRM writes. Current `customer-store.sql` and `refresh-newbase-source-v2.ps1` include `name_short,name_full,person_name,inn`, **not phone**. The existing project review confirms TEST OData exposes a `Catalog_Контрагенты_КонтактнаяИнформация` table part (`docs/NATIVE_BUYER_CHANGE_TRIGGER_S4_V2.md`); its exact columns, type codes, linkage and meaningful phone contents have NOT yet been verified. Inspect real TEST OData metadata and read-only aggregates before implementing the phone extraction. Do not invent `Catalog_Контрагенты.Phone` or assume phone storage and ownership. Add nullable phone fields in a migration with database backup and backread acceptance. Use only confirmed 1C phone values.

Existing initial import puts INN in comments. Confirm CRM requisites and preset, use `crm.requisite.list/add/update` with readback to map real INN and legal full name. Use Bitrix24 `fm` native phone fields with readback. Protect pre-existing user-entered values: define ownership and conflict handling, do not overwrite unrelated data. Ensure names/field review queues reach an understood final state. At minimum test examples of each LEGAL, PERSON, and REVIEW.

### Accepted 1C phone-source metadata — real SRV V3 receipt, 18 October 2026

User accepted V3: `UTC=2026-10-18T15:50:53Z;STATUS=PASS;SOURCE=TEST_NEWBASE;ENTITY_SETS=1492;CONTACTINFO_SET=YES;ORIGIN=PART_ENTITY_SET;PROPERTIES=16;NAVIGATIONS=1;ONEC_WRITES=0;BITRIX_REQUESTS=0;CUSTOMER_DATA_EXPORTED=0`.
1C OData source `Catalog_Контрагенты_КонтактнаяИнформация` with row identity `Ref_Key,LineNumber`. Metadata confirms string columns `Тип`, `Представление`, `НомерТелефона`, `НомерТелефонаБезКодов`, `Значение`, plus `Вид_Key`; there are more contact/address fields. Metadata alone does not prove which phone rows are populated, owner/reference matching, data quality or Bitrix synchronization.

A full read-only coverage worker `bin/audit-newbase-phone-coverage-readonly-v1.ps1` now exists and is offline-tested, with a no-trigger admin launch `bin/start-newbase-phone-coverage-readonly-v1.ps1`. It joins contact rows by owner Ref_Key to the 6433 eligible source GUIDs in local SQLite, checks stable paging and count, reports only aggregate coverage and never exports individual phone values or alters source/CRM/DB. GitHub Windows checks PASSED, worker SHA256 `209179b2d4b9adcecaa3e6cb7c2d9c391c086e9cb498c1fcba6e81e00cb6b6d2`, launcher SHA256 `ac74905482fff3ad0af395ee2b82f0ef7487d71dc72f792cda37a142df342415`. This audit has NOT been installed or executed on physical SRV yet; do not state actual phone coverage before a real receipt. Auto-update remains off. After real coverage acceptance, build a backed-up SQLite phone field migration, staged CRM field update pilot and backread acceptance.

## Task 3 — Daily ongoing changes (not a second initial import)

The existing `refresh-newbase-source-v2.ps1` has full-source scan and local `msp_auto_outbox` detection, but the existing `pump-newbase-bitrix-batch-v2.ps1` only creates new entities; it marks existing ones `UPDATE_REQUIRED` rather than applying source changes. A separate `update-newbase-existing-once-v1.ps1` is already implemented and offline-tested for ONE existing GUID with optional explicitly approved update of CRM item and company requisite; it is NOT installed, bulk-accepted or automation-ready (`docs/ONE_BUYER_UPDATE_ACCEPTANCE_V1.md`). Reuse its tested identity/ownership/backread conditions rather than inventing a competing update path. `msp-newbase-auto-tick-v2.ps1` can rescan each 15 minutes and is not equivalent to a single morning run. Do **not** enable `install-newbase-auto-v2.ps1` without repair and validation.

Use one daily time, e.g. 08:30 SRV local, to read complete active 1C buyers, atomically refresh durable SQLite, compare by GUID/fields, and enqueue only NEW/CHANGED. Existing Bitrix CRM cards are updated by ID, new GUIDs created once. Keep per-record confirmed state; survive network errors and resume without duplicates; distinguish REMOVED / disabled without automatic destructive CRM deletion. Update target phone/requisite fields only after ownership checks.

Acceptance: a new synthetic TEST 1C buyer is present in SQLite and CRM after a single daily cycle, a changed customer updates the same CRM ID, unchanged records generate no CRM writes, interruption can be safely replayed, 1C production untouched, no secrets/PII printed. Activate the recurring task **only after all acceptance tests**, with user confirmation of schedule and operational access.

## Status format at each task

Report exactly: **Completed**, **Not completed / blockers**, **Evidence**, **Next action**.
No task is declared complete merely because a GitHub test passed or a Windows task was started.

# Bitrix24 customer scope — user-confirmed 2026-10-15

## Objective
**ALL_ACTIVE_BUYERS_INCLUDED**: Bitrix24 must make the company's customer
directory available to staff: both organizations and natural persons.
People may buy occasionally, and **absence of INN must not suppress or exclude
a natural person**. Sync runs centrally, not once for each person searching.

## Confirmed TEST 1C audit (snapshot only, not hard-coded future gate)
- `Catalog_Контрагенты`, `Покупатель eq true and DeletionMark eq false and Недействителен eq false`.
- **6,433** active buyers; **1,941** `ЮридическоеЛицо`, **4,486**
  `ФизическоеЛицо`, **6** other/unclassified.
- Full-name nonblank 5,577 / 6,433; INN nonblank 1,925 / 6,433;
  both nonblank 1,912 / 6,433. These numbers cover all buyer types.
- Legal with nonempty INN: 1,402 / 1,941. These are not the number of
  importable contacts nor the total final Bitrix24 customer population.
- Full scan: 65 pages, 6,433 unique `Ref_Key` values, no duplicates.
- All counts from read-only TEST 1C; zero Bitrix REST calls and zero 1C writes.

## Rules for every future implementation
1. `CUSTOMER_SCOPE=ALL_ACTIVE_BUYERS`, **not** `LEGAL_ONLY`.
   `ФизическоеЛицо` MUST be retained in the source index and made
   available in the future Bitrix24 directory even when `ИНН` is empty.
2. `ЮридическоеЛицо`: user requires full official organization name
   (`НаименованиеПолное` -> prospective `RQ_COMPANY_FULL_NAME`) and
   `ИНН` (prospective `RQ_INN`); missing fields go to data-quality
   queue for enrichment, not global customer exclusion. Short display
   name may come from `Description` only under agreed mapping.
3. `ФизическоеЛицо`: `INN_REQUIRED=NO`. Use `Ref_Key` as durable
   identity, carry legal/person category and choose a human-readable
   label from verified source fields (`ФИО`, `Description`,
   `НаименованиеПолное`) with a documented fallback/exception policy.
   Do not invent names or split `ФИО` automatically.
4. The **six other/unclassified** buyers remain in scope as
   `TYPE_REVIEW_REQUIRED`; must not be silently discarded.
   Investigate whether individual entrepreneurs or other business
   categories exist before final company/contact entity mapping.
5. Working Bitrix24 mapping is **candidate only**:
   company+requisite for legal entities, contact for natural persons.
   Confirm actual portal REST fields, presets, duplicate rules and
   permissions before implementing. Maintain 1C `Ref_Key` to Bitrix ID
   mapping and stable `ORIGINATOR_ID` / `ORIGIN_ID` namespace.
6. Do not transfer tax identifiers, ID documents, date of birth or
   other unnecessary personal fields for natural persons by default.
   Phones/email are optional after validating table-part meanings and
   access controls.
7. Avoid per-user full OData scans: design one local encrypted/protected
   index on SRV, a durable delta queue, controlled OData page reads and
   throttled Bitrix sync. Bitrix users query Bitrix's synchronized
   directory, not the 1C server directly.
8. Preserve `MspBitrix24Bridge` in **SAFE_IDLE**. No Bitrix calls,
   no 1C writes, no changes to the existing 1C agent/system task,
   until separately approved.

## Selected update mechanism (15 Oct 2026)
- User explicitly chose **Option B**: source-side native 1C change
  registration (exchange-plan service), with a durable SRV inbox.
- Preferred *local storage proposal* is SQLite at
  `C:\ProgramData\MspCustomerStore\data\customers.db`, subject
  to legacy OS/provider and encryption/ACL validation.
- JSON is for event/API transport only, not the master directory.
- Integration remains conceptual; see [SYNC_ARCHITECTURE_OPTION_B.md](SYNC_ARCHITECTURE_OPTION_B.md).
- No 1C metadata/config write or Bitrix24 sync enabled without approval.

## Primary Bitrix24 workflow (user-confirmed, 15 Oct 2026)

Bitrix24 must provide a **full searchable catalog** of active 1C
buyers. This DOES NOT require automatically creating all 6,433 CRM
cards. The preferred integration candidate is `CRM_DETAIL_SEARCH`:
show external 1C results in client selection, preserve existing CRM
matches, create/link CRM card only on explicit user selection and after
duplicate validation. Its documented UX requires at least 3 characters
and an extra application choice click.
See [BITRIX_ALWAYS_SEARCHABLE_DIRECTORY.md](BITRIX_ALWAYS_SEARCHABLE_DIRECTORY.md).
No 1C full scan per user query; network/service accessibility remains an
unresolved design gate.

## Next acceptance work
- Inspect safe **per-type aggregate** name completeness, plus the
  six unknown type values, without record export.
- Design unified local cache/data model for both legal and natural
  buyers with no mandatory INN for natural persons.
- Independently verify the Bitrix24 portal company/contact model.
- Only then plan staging sync in small chunks with deduplication,
  observability, retry control, and rollback strategy.

The optional `scan-legal-required-fields.ps1` is a **diagnostic** only:
it must NOT become the sole ingestion logic or prerequisite for
access to physical-person customers.

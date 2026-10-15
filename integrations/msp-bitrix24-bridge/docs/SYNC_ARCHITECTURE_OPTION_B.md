# MSP Bitrix24: selected synchronization architecture — Option B

**Status 2026-10-15: CHOSEN BY USER, DESIGN ONLY, NOT DEPLOYED.**

## Business scope (non-negotiable)

All active buyer counterparties must be available to Bitrix24:
- 6,433 active buyers in the current TEST 1C snapshot.
- 1,941 `ЮридическоеЛицо`; 4,486 `ФизическоеЛицо`; 6 other/unclassified.
- Natural persons without INN MUST NOT be excluded, even occasional buyers.
- Organizations should include full official name and INN in the future Bitrix
  requisite mapping; missing fields require review, not deletion from local index.
- Stable 1C `Ref_Key` must be the source identity. Do not match by name or INN alone.

## User-selected Option B: register changes at the 1C source

- Use the native 1C change-registration mechanism (e.g., dedicated exchange
  plan node and allowed autoregistration), NOT recurrent full 6,433-row scans.
- Register new, changed and deleted/invalidated counterparties, including
  changes relevant to contact details, name, buyer eligibility and legal type.
  Verify the particular UNF configuration's metadata/event support.
- A **dedicated, read-only-like extraction interface** must be designed to
  fetch registered change IDs/batches from 1C to physical SRV. Standard
  1C OData Catalog GET alone has NOT been proven to expose the exchange-plan
  registration queue. It MUST NOT be presumed to do so.
- For each changed GUID, a separate worker fetches *current* required
  fields via the approved local OData endpoint and updates local store.
- Ack change registration only AFTER the event and relevant state are
  durably stored on SRV. Use cursor / message number and safe replay
  to avoid losing change events when jobs fail. If the transaction order
  cannot be guaranteed, fail closed and reconcile.
- This mechanism may require metadata/configuration changes, permitted
  extensions, or extra 1C processing and admin/developer permissions.
  Nothing may be installed or changed in production based on this document.
  The original system OData agent and test/production 1C services must remain
  untouched during design and read-only acceptance.

Official mechanism:
- https://v8.1c.ru/platforma/sluzhba-registratsii-izmeneniy/
- https://its.1c.ru/db/content/metod8dev/src/developers/platform/metod/dataexchange/i8102276.htm

## Local store on physical SRV (proposed technology)

Preferred format: **SQLite**, `C:\ProgramData\MspBitrix24Bridge\data\customers.db`.
This path is a proposal only. It has NOT been created or deployed.
It is a transactional indexed local database, **not** a huge JSON array/file,
Excel sheet, or a file on a network share.
Verify compatible SQLite provider and bitness for Windows Server 2008 R2,
.NET runtime and PowerShell 2.0 before final technology approval.
SQLite is not encrypted by default. ACLs, secrets, disk/backups encryption,
monitoring and retention must be approved before storing customer data.
If WAL is used, files `customers.db-wal` and `customers.db-shm` may also
appear. All SQLite read/write operations must run on SRV (no SMB direct access).
One designated local writer; concurrent readers should access via controlled
SRV service/API as needed.

Logical tables (schema proposals, not yet deployed):
- `customers`: `onec_guid PRIMARY KEY`, `category`, `display_name`,
  `full_name`, nullable `inn`, `active`, `needs_review`,
  `source_version`, `payload_hash`, `updated_local_at`.
  Natural person's `inn` is nullable by design.
- `change_inbox`: `source_event_id UNIQUE`, `onec_guid`, `action`,
  `source_cursor`, `received_at`, `ingest_state`.
- `bitrix_outbox`: `onec_guid`, `operation`, `payload_hash`,
  `attempts`, `status`, `retry_after`, with deduplication.
- `bitrix_links`: `onec_guid UNIQUE`, `bitrix_entity_type`,
  `bitrix_id`, `last_sent_hash`, `last_success_at`.
- `sync_checkpoint`: durable cursor, ack and run status.
- `sync_journal`: structured non-PII operational events only.

JSON is acceptable for **small transport envelopes** (GUID, operation,
event/version); never as the main durable mutable directory. Client payloads
must not go to GitHub, VPS logs or Telegram.

## Operating sequence

1. Create/verify isolated change-registration on TEST 1C with explicit
   authorized 1C developer review. Include dependent contact-data changes.
2. Start durable registration before initial snapshot or use a coordinated
   replay/snapshot cursor; otherwise changes during first import may be lost.
3. Initial single read-only backfill of all eligible customers (6,433
   currently), including all types; page and verify uniqueness.
4. Worker on SRV polls for new registered GUIDs (proposed cadence, subject
   to load measurements), deduplicates and loads only changed clients.
5. SRV writes local `customers` and `change_inbox` atomically.
   1C registration can then be acknowledged as appropriate.
6. Independently, an authorized Bitrix search application can query the
   local synced index through an approved secured low-latency interface.
   Search itself DOES NOT create CRM entities or touch 1C.
7. If a user selects an external 1C customer absent from CRM, the app
   checks linkage/duplicates, then creates or links a company/contact
   on demand. Separately approved bulk preloading remains optional.
   Never silently delete a Bitrix card or create a duplicate.
8. Rare controlled reconciliation runs remain as fallback and safety audit,
   not the default synchronization mechanism.

## Searchable directory is the primary user workflow

The user clarified that the business objective is **universal, current
search access** from Bitrix24 (not necessarily precreation of all 6,433 CRM
entities). Prefer evaluating the officially supported `CRM_DETAIL_SEARCH`
external-client finder, with on-demand safe CRM entity creation/linking
after selection, before any bulk CRM import design.
See [BITRIX_ALWAYS_SEARCHABLE_DIRECTORY.md](BITRIX_ALWAYS_SEARCHABLE_DIRECTORY.md).

The separate Bitrix24 search widget requires a low-latency reachable
authenticated endpoint. The SRV outbound polling transport does **not**
provide this by itself, and no network route is yet approved.
An option involving a protected minimal online search projection would
require separate approval before moving any client data from SRV.
Existing SAFE_IDLE remains unchanged.

## Explicit current status

- `MspBitrix24Bridge` Windows task remains **SAFE_IDLE** with
  `ACTIVE=0`, `CUSTOMERS_READ=0`, `PRODUCTS_READ=0`,
  `INVOICES_WRITE=0`.
- No SQLite file created, no plan/exchange node added, no 1C writes,
  no Bitrix24 API calls and no customer records exported by this design.
- Change-registration access through 1C OData is **UNVERIFIED**.
- Next safe work: check TEST UNF 1C existing exchange plans and extension
  compatibility/permissions read-only, select extraction mechanism,
  prototype an empty local DB schema offline in CI, inspect security
  requirements, and prepare a rollbackable TEST-only acceptance plan.

# Existing buyer updates: no false-positive success (TEST NewBase)

Status: **offline code + CI safety only**. This is not an approved mass CRM import and
does not activate SRV scheduled tasks or production 1C.

## Defect found in the existing batch worker

The old `pump-newbase-bitrix-batch-v2.ps1` matched an existing Bitrix24
company/contact by `originatorId=MSP_ONEC_NEWBASE` and `originId` equal to the
1C `Ref_Key`. It then called `MarkDone` without comparing or updating the
customer's business fields. Because `MarkDone` removed its `UPSERT` outbox row,
a name/INN change could be silently lost while the run reported success.

A second race existed: between reading an outbox item and receiving Bitrix24
confirmation, a new source change might arrive for the same GUID. Unconditional
outbox deletion could discard that newer change.

## Fixes in PR #14

- The existing-origin path is now **fail-closed for field synchronization**:
  a matched origin GUID sets the local outbox state to `UPDATE_REQUIRED`
  using a source-stamp condition. No CRM update is issued and the event is
  not acknowledged as synchronized. This includes a previously created
  entity whose fields may have drifted.
- `MarkDone` for **newly created and back-read** CRM records now accepts
  the exact source `changed_utc` captured with the work item and only deletes
  an outbox `UPSERT` with that same stamp. A later outbox version survives.
- The source full-scan writer stamps new changes with seven fractional UTC
  digits, reducing same-second collisions. A fully monotonic generation
  counter would still be stronger; introduce that before high-concurrency
  production use.
- Any unmatched or ambiguous duplicate remains `HELD`; it must never be
  silently linked or deleted.
- The pump reports `RESULT=PARTIAL` rather than `PASS` when an existing
  CRM match still needs a verified update.
- New `audit-newbase-bitrix-outbox-v1.ps1` reads **aggregate counts only**
  from the machine-owned SQLite DB using `-readonly`, distinguishing
  `UPSERT`, `UPDATE_REQUIRED`, `HELD`, `REMOVED`, and unexpected values,
  plus mapped records and unresolved CRM operations.
- Offline synthetic SQLite tests verify newer outbox work survives an old
  confirmation; an existing-origin mapping no longer invokes `MarkDone`.

## Required next stage before existing-customer CRM updates

1. Design a separate **bounded, explicitly gated** CRM update worker.
   Verify the current `crm.item.get` origin ID and CRM type before any write.
2. For a company, update only approved fields (title, and validated company
   requisite fields). Verify the selected `crm.requisite.list` result and
   its `ENTITY_ID`/`ENTITY_TYPE_ID`; reject missing or ambiguous matches.
   Do not use INN or name alone as identity.
3. For a contact, decide exact FIO-to-field policy; do not overwrite Bitrix
   `name`, `lastName` or multifields based on an unverified split.
4. Read the CRM entity (and requisite if applicable) back after the update.
   If an HTTP response is ambiguous, **read first, never blindly retry**.
   Only then transition the exact pending source generation to completed.
5. Confirm conflict ownership: which fields 1C owns, and which staff may
   edit independently in Bitrix24. Prevent changes in unrelated CRM fields.
6. Cover rapid consecutive updates, same-GUID duplicate work, CRM outage,
   source deactivation, type migration, stale mappings, multiple requisites,
   missing INN and `REVIEW` category. Existing CRM records should never
   be deleted automatically.
7. Real transfers remain **TEST-only** until separate production approval.
   Production 1C OData and exchange-plan registration are independent gates.

References:
- https://apidocs.bitrix24.com/api-reference/crm/universal/crm-item-update.html
- https://apidocs.bitrix24.com/api-reference/crm/requisites/universal/crm-requisite-update.html
- https://apidocs.bitrix24.com/api-reference/crm/requisites/universal/crm-requisite-list.html

Data remains on physical SRV. No customer rows, names, GUIDs, INNs,
Bitrix24 tokens or response bodies in GitHub.

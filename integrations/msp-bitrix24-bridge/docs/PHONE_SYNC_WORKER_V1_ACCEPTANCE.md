# SRV -> Bitrix24 phone synchronization, version 1

**Implemented in PR #14; real CRM writes not yet accepted.** First stage is a local-only durable queue, followed by a separately authorized single-card live pilot. There is no automatic schedule and no new CRM buyer creation in this stage.

## Accepted source

Physical SRV **customers.db** contains 6,433 active buyers, 6,433 source-to-CRM identities, 6,433 names, 1,925 populated INNs, and 4,068 phone rows for 4,067 buyers. A preserved backup comparison proved `INN_NAME_DIFFERENCES=0`. Format screening: 4,032 preliminary phone candidates for 4,031 buyers; 36 review rows held back. One buyer has two candidate phone rows. These are local source facts, not proof of updated Bitrix fields.

## Components

1. `bin/prepare-bitrix-phone-queue-v1.ps1` creates `msp_bitrix_phone_queue` **inside the existing customers.db**, joining only active customers with their existing, unique `msp_initial_map` CRM identity. All original phones/names/INNs remain unchanged. The queue contains exactly 4,031 PENDING identities covering 4,032 format-candidate phone rows (1,089 single-phone companies, 2,941 single-phone contacts, 1 two-phone buyer). It backs up the existing local DB first, checks cardinalities and SQLite integrity, and writes a sanitized receipt. **No CRM requests.**
2. `bin/start-bitrix-phone-queue-v1.ps1` runs step 1 as a single non-repeating Task Scheduler job under `LOCAL SERVICE` after explicit administrator invocation, with immutable SHA and PS2 syntax validation.
3. `bin/msp-bitrix-phone-sync-worker-v1.ps1` has `-Mode Pilot -MaxCards 1` and `-Mode Batch -MaxCards N` (1–20). In Pilot it selects **one** queued company with one source phone; in Batch it requires an accepted Pilot PASS receipt. Before writing, it calls `crm.item.get` in REST batch form, verifies source `originId/originatorId`, CRM ID and zero existing native PHONE multifields, and records all existing non-phone multifields. It records SQLite `INTENT` for every card **before** sending one write batch, using `crm.item.update` with `fm[n0]` (or `fm[n1]` for the second source phone); the write path has **no retries**. A subsequent independent `crm.item.get` must confirm the expected phone values and unchanged other `fm` entries before each item becomes `DONE`. Unverified operations are `UNCERTAIN`, not PENDING; they cannot be retried automatically. No `crm.item.add` anywhere in this worker.
4. `bin/start-bitrix-phone-pilot-v1.ps1` is a separate non-repeating, hash-pinned launcher for **at most one live CRM update**, only after successful local queue acceptance. No Timer, no unattended bulk mode.

## Runtime and bounds

- Platform: physical SRV WinServer2008R2/PS2 x64/CLR2, `LOCAL SERVICE` account. DPAPI Bitrix REST credential never leaves physical SRV.
- Batch limits: at most **20 CRM cards in one write batch** in the current conservative implementation; official Bitrix REST `batch` maximum is **50 operations**. Bigger batches require measurement and independent approval.
- Throughput has **not yet been measured** on the actual Bitrix tenant. Do not claim subminute or fixed backfill duration until one-card and 20-card batches are measured, including backread and CRM automation impacts.
- The local queue is an initial one-time backfill, **not** yet a fully implemented continuous change-feed from 1C. The future incremental feed must reconcile changed phone values, INN and full name, and update the same stable CRM identity. The daily recurring schedule is OFF pending safe end-to-end tests and explicit acceptance.
- Do not reimport the original 6,433 CRM cards. Do not change production 1C. Do not export phone values or user identifiers to console, GitHub or CI.

## Live acceptance required

1. Physical SRV queue task completed, `TASK_STATE=3`, `LAST_RESULT=0`, receipt `STATUS=PASS`, independently read SQLite queue counts `4031:4032:1089:2941:1`.
2. One physical SRV Pilot task completed successfully; pre/post independent `crm.item.get`, receipt `STATUS=PASS;MODE=Pilot;POST_BATCHES=1;VERIFIED=1;CRM_WRITES=1;BACKREAD=PASS`. On any ambiguity **do not rerun**; perform read-only reconciliation.
3. Only after step 2, user-authorized batch invocations and per-record accepted receipts to account for all 4,032 phone candidates and 36 holdouts. Confirm unchanged non-phone multifields.
4. Add native INN/requisites/full-name delta processing, incremental 1C refresh with phone change detection and a controlled recurring schedule; test with changed test customer and truly new customer. The integrated pipeline is not complete until these are accepted.

## Official API references

- https://apidocs.bitrix24.com/settings/how-to-call-rest-api/batch.html
- https://apidocs.bitrix24.com/api-reference/crm/universal/crm-item-update.html
- https://apidocs.bitrix24.com/tutorials/crm/how-to-edit-crm-objects/how-to-change-email-or-phone.html

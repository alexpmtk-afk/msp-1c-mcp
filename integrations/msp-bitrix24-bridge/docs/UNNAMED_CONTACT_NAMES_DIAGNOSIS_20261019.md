# Bitrix24 contact names — source fallback regression and correction gates (2026-10-19)

## Evidence

User screenshot of Bitrix contacts showed literal `[1C UNNAMED] <GUID>` entries, including two visible list rows bearing the same literal GUID text. These are **not yet proof of duplicated actual `originId`**; the two rows must be checked in Bitrix CRM by their real IDs, independently of title.

Physical SRV local SQLite read-only query:
```
ACTIVE=6433;OLD_UNNAMED=546;RECOVERABLE_FROM_SHORT=546
NAME_REVIEWS=123;FIELD_REVIEWS=2254
```

The active source contains **546 PERSON records** with empty `person_name` and `name_full`, but non-empty `name_short`. Their old initial import fallback generated technical literal `[1C UNNAMED] <GUID>`, even though source `name_short` was available. Original V5 logic in `bin/import-all-newbase-buyers-once-v5.ps1`: contact title = `person_name`; if absent, use `name_full`; if both empty use GUID; **no `name_short` fallback for PERSON**. Original V5 also sent the full title as CRM contact `name`, not split into `name/lastName/secondName`. Source name/INN data on SQLite remained exactly unchanged during the separate phone migration (`INN_NAME_DIFFERENCES=0`).

The 123 pre-existing `NAME_MISMATCH` review entries and 2254 `FIELDS_REVIEW` entries are separate counts, **not** interchangeable with 546 placeholder-name source candidates. Native INN/requisites remain incomplete. Phone pilot + batch5 + batch20 performed **26** confirmed writes/readbacks; **4005** phone-queue buyers remain. Pause any mass 4005-item bulk run while identifying name/dedup implications.

## Next controlled step — live read-only CRM audit

`bin/audit-bitrix-unnamed-names-readonly-v1.ps1`: PS2/CLR2, physical SRV only, LOCAL SERVICE only, uses existing Bitrix DPAPI webhook, `sqlite3 -readonly`. Restricts input to exactly **546 source PERSON rows** and 546 distinct matched contact CRM identities, from the existing local `msp_initial_map`. Queries `crm.item.get` and `crm.item.list` (10 customers per REST batch, 20 GET/LIST commands) to check real `originId`, `originatorId`, mapped CRM ID, exact current placeholder vs recovered `name_short`, presence of other native FIO subfields, and whether a source `originId` maps to more than one CRM contact. No customer fields/PII are printed or saved; only aggregate counts. No CRM, source or SQLite content writes. One-shot launcher: `bin/start-bitrix-unnamed-names-audit-v1.ps1`, strict worker SHA, no task trigger.

**Do not correct names blindly.** Treat any duplicate `originId`, changed/mismatched CRM title, or non-empty other name parts as separate manual-review categories. Proceed to guarded single-card display name pilot using unchanged CRM ID only after the live read-only audit is accepted. Do not merge/delete CRM cards by matching visible titles.

## Proposed correction design (not yet deployed)

For independently verified unique mapped placeholders, choose source `name_short` as the new visible CRM contact name. Correct native `name,lastName,secondName` with a separately verified naming policy and source content; do not infer first/last patronymic from strings without review when ambiguous. Verify GUID/origin and read back name and all previous phone/email fields after every update; no create/delete. Preserve preexisting user edits. Keep future 1C changes and full-source CRM validation separate from initial name bug fix.

## Actual physical SRV live audit acceptance, 19 October 2026

User-provided scheduler `TASK_STATE=3;TASK_LAST_RESULT=0` and receipt `UTC=2026-10-19T07:18:05Z;STATUS=PASS;SOURCE=TEST_NEWBASE;SCANNED=546;PLACEHOLDER=546;ALREADY_NAMED=0;DIFFERENT_NAME=0;OTHER_FIO_PARTS=0;DUPLICATE_ORIGIN=0;IDENTITY_PROBLEMS=0;CRM_READ_ERRORS=0;BATCHES=55;CRM_WRITES=0;ONEC_WRITES=0;SQLITE_WRITES=0;PII_EXPORTED=0`. All 546 target contacts are uniquely mapped and still show the historical technical placeholder, with zero source-origin duplicates or identity errors. This does **not** prove that visually identical titles elsewhere are the same CRM entity, and it does not evaluate the quality of every `name_short` string.

Single-contact correction program `bin/repair-bitrix-unnamed-name-pilot-v1.ps1` and independent hash-pinned one-shot installer `bin/start-bitrix-unnamed-name-fix-pilot-v1.ps1` are committed and PS2 syntax tested. The worker first backs up the current SQLite, initializes a 546-row durable `msp_bitrix_name_fix` queue inside `customers.db`, confirms a single contact still has the exact `[1C UNNAMED] <GUID>` placeholder and source origin/CRM identity, checks native FIO parts are empty, snapshots multifields, marks a durable `INTENT` **before** issuing one `crm.item.update` of `fields[name]`, then separately reads back the new source `name_short` and checks FIO and all original multifields unchanged before marking `DONE`. No create, delete, recurring schedule, or subsequent mass update. Any ambiguous execution is `UNCERTAIN` and must not be retried without inspection. Source 1C remains read-only. The test suite and Windows PS2 parse suite have passed; physical SRV execution/CRM write not yet verified.

# Bitrix24 customer transfer — delivery contract

This is an execution contract, not an indication that the integration is finished. Machine-readable truth: `../delivery-gates.json`. GitHub tests and syntax checks alone **never** prove a customer field was saved in Bitrix24.

## Scope and next outcome

**Single active task:** Add one source telephone to **one existing mapped company** in Bitrix24, then independently read back the field. Do not conduct another global source audit, import buyers again, or introduce a new architecture. The original 6,433 buyer mappings and 4,068 source-phone rows remain intact. The phone-format screen yields 4,032 provisional candidates and 36 records requiring separate review.

The action remains **not implemented / not executed** until a verified, runnable PS2 package is available on SRV and a real success receipt has been examined. After one-card E2E success, separately implement the bounded bulk backfill, audit individual readback results, then native requisites/name corrections and daily sync. No customer duplication and no changes to production 1C.

## Mandatory gates (must pass in this order)

1. **Business acceptance first.** Define what will appear in the actual CRM card; define the source and destination field, expected count, independent check, and error behavior. Do not claim field-level success from mapping counts.
2. **Complete delivery artifact.** Worker plus one-shot launcher plus dependent modules and requirements manifest; CI tests for PS2/.NET2 compatibility, mocked API responses, safe read/update behavior, no implicit retries, and a clean sandbox deployment from an empty staging directory. Check every required path on SRV **before** registration. Do not give a command containing a nonexistent file.
3. **One real E2E on physical SRV.** For phone updates: select only an active source GUID that uniquely maps to an existing CRM ID; check origin and existing native PHONE fields via `crm.item.get`. Persist an intent before attempting a single update. Do not automatically re-post after an uncertain response. Verify via a fresh GET that one correct phone is present and unrelated contact fields remain intact.
4. **Operational acceptance differs from tests.** `TESTS=PASS`, `TASK=STARTED`, `READ_ONLY=PASS`, `SOURCE_SNAPSHOT=PASS`, `CRM_FIELD_BACKREAD=PASS` are different outcomes. Only `CRM_FIELD_BACKREAD=PASS` after actual write is a completed one-card phone transfer. The source of any acceptance is a sanitized SRV receipt, not a predicted return code.
5. **Bulk deployment gated by one-card acceptance.** Persist per-card progress, constrain API rate and timeouts, verify every changed card with an independent read, preserve CRM user-entered data, distinguish confirmed success and uncertain outcomes. Separate 36 review records; do not invent phone numbers or silently discard.
6. **Final release gate.** Do not say "Bitrix integration complete" until CRM phone field outcomes, native INN/full-name requisites, field-review reconciliation, and a real tested daily new/changed-buyer cycle have acceptance receipts. Keep `AUTO_UPDATE=OFF` until explicitly authorized.

## Failures we must not repeat

| Previously observed failure | Required prevention |
| --- | --- |
| Import created/mapped 6,433, but did not populate native PHONE/INN fields | Business-field acceptance is distinct from `MAPPED=6433` |
| Used XML feature unavailable in PowerShell 2.0 / .NET 2 | Windows PS2 parser and CLR-compatible runtime test before SRV run |
| Bitrix shared core missing from SRV installation | Fresh-install dependency manifest and preflight verification of every required file |
| SQL missing parentheses and returned syntax error | Test actual SQL in SQLite offline; generate nested expressions mechanically |
| HTTP 406 / transient OData count outage | Proper content negotiation and bounded retries **for safe reads only**; check response and method separately |
| Multiple read-only audits after all facts were known | Stop probing and implement the next missing business action |
| Suggested another agent instead of delivering a working component | Own the code and runtime instructions in this project; report tool blockers instead of pretending work is complete |
| Attempt to publish write worker was blocked | Report `NOT_IMPLEMENTED`; never manufacture download links or imply the CRM write happened |

## One request from SRV, one answer from assistant

For each next execution ask for **one** minimal PowerShell 2.0 command; after its output interpret the receipt, decide the one corrective action, and continue. When blocked, state exact reason and give a specific next technical action. Avoid repeated status prompts, unnecessary new audits, or diversions to Codex.

**Controls:** TEST `D:\DATA\NewBase` read-only; production 1C untouched; raw client data and credentials only on physical SRV; no PII in console/GitHub/CI; no duplicate CRM cards; no automatic Bitrix writes until the approved one-shot and later explicit bulk gate.

## Current gate truth

- Source-to-CRM mapping: 6,433 accepted **with 2,254 field reviews and 123 name reviews**.
- Source telephones: 4,068 records / 4,067 distinct buyers in SRV-local SQLite; 4,032 format candidates and 36 review cases.
- Bitrix native PHONE audit: all 4,067 target cards read, zero phones currently present.
- CRM telephone writes: **zero**; one-card update **not done**; bulk backfill **not done**.
- INN/name field reconciliation: **not done**. Daily sync: **off**.

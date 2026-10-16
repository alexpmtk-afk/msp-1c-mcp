# Direct SRV → Bitrix24 CRM sync (no VPS in customer data path)

## Approved architecture as of 2026-10-16

Physical SRV (Windows Server 2008 R2, native PowerShell 2.0)
→ protected LocalService SQLite buyer index (6,433 snapshot records)
→ **outbound HTTPS TLS1.2 directly to** `https://b24-uwmjda.bitrix24.ru/`
→ Bitrix24 CRM REST.

REMOTE VPS, Hermes, GitHub Actions and the old HTTP relay are **not** transport participants. The existing `bitrix-search-outbound-once.ps1` is a **disabled legacy prototype**, not the implementation of direct sync. Never enable it by reuse.

## Read-only acceptance sequence

1. Native PS2/LocalService checks already PASS; installed JSON1 worker and rollback copy verified. Worker remains disabled.
2. `probe-bitrix-direct-https-service.ps1` checks TLS and HTTPS reachability to the **one pinned host**, with zero REST calls or credentials. The runner registers a **single triggerless** LocalService task for one test only, and removes it on PASS. On FAIL, do not retry before diagnosing the task and receipt.
3. Provision a dedicated **read-only** Bitrix24 incoming webhook under a service/technical employee with `crm` scope. This is an explicit administrator operation. Do not paste its full URL or token into chat, GitHub, Issues, Actions, or logs. Secrets are for SRV protected runtime storage, provisioned separately.
4. Make exactly one credentialed **read-only** `crm.item.list` request using POST to the pinned host; validate token/scope, fail closed and report only HTTP code and aggregate counts, never names/GUIDs externally. Verify company type `entityTypeId=4` and contact type `entityTypeId=3`.
5. Enumerate CRM pages with `start` increments of 50, respecting `next` and rate limits. Compare against 1C snapshot locally on SRV only; no writes in discovery phase. Existing company/contact names and possible duplicates may require explicit resolution.
6. Distinguish LEGAL companies and PERSON contacts; REVIEW/unknown buyer types (6) require a held queue rather than automatic classification. 6,433 is a verified source count, **not** a count of new CRM entries to create.
7. Plan idempotent mapping: native `originatorId` identifies the source (stable value, e.g. `MSP_ONEC`), `originId` is the 1C GUID, and `originVersion` records a meaningful source version. Also compare existing CRM entities by name/INN/phone where those fields exist; absence of GUID mapping alone does **not** authorize creation. Never overwrite CRM edits or create duplicates without separate approval.
8. A bounded **synthetic** create/update (if approved later) must be followed by reverse reading, idempotency proof, rollback method and only then a separately approved production batch.
9. The source FTS5 index is currently a **snapshot**, because 1C Option B delta/change tracking remains paused. Do not claim live synchronization until incremental change capture has been accepted.
10. Avoid any 1C writes, REST mutations, bulk exports and periodic automatic uploads until the corresponding acceptance gate is met.

## API documentation and distinctions

- [Bitrix24 incoming webhooks](https://apidocs.bitrix24.ru/local-integrations/local-webhooks.html): secure URL with employee-bound scope/permission. No external callback server needed for outgoing calls.
- [`crm.item.list`](https://apidocs.bitrix24.ru/api-reference/crm/universal/crm-item-list.html): read-only, 50 rows/page; company 4, contact 3; can select `id`, `title`, `originatorId`, `originId`, `originVersion`.
- [`crm.item.add`](https://apidocs.bitrix24.ru/api-reference/crm/universal/crm-item-add.html): **future write phase**, disabled.
- [CRM origin fields](https://apidocs.bitrix24.ru/api-reference/crm/main-entities-fields.html): source identifiers/version prevent accidental overwrites when designed and enforced correctly.

The prior `CRM_DETAIL_SEARCH` plan required an external inbound HTTPS handler and was **not** a list upload. Under the user's revised direct-upload requirement, do not install or activate that legacy approach or the REMOTE relay.

## Pending capability gates

- Validate exact SRV TLS/certificate and HTTP response.
- Confirm portal CRM availability and proper **read-only** credential on SRV; do not request secrets in chat.
- Make a minimal read-only CRM API call on SRV and backread sanitized metadata.
- Confirm reconciliation and dedup before *any* write.

**Status:** direct HTTPS source code and offline tests only. No live API or customer export acceptance yet.

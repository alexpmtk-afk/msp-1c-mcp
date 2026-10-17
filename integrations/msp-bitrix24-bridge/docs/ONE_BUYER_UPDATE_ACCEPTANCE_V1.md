# S5 — One existing buyer: TEST NewBase → Bitrix24

Status: **code and offline CI only**. Not installed on SRV. Not activated.
Not a full buyer synchronization or production 1C trigger.

## What has been implemented

Script: `bin/update-newbase-existing-once-v1.ps1`.

The only source is the existing machine-owned TEST SQLite snapshot
`C:\ProgramData\MspCustomerStore\data\customers.db`. No request or write to
either test or production 1C is made. Read-only Bitrix24 requests use the
already enrolled DPAPI-protected HTTPS webhook under `LOCAL SERVICE`.

Default invocation is **read-only** and requires one lowercase 1C GUID:
`-OnecGuid <guid>`. No bulk enumeration and no scheduler registration.

The script reads only one `UPDATE_REQUIRED` outbox item. It obtains a
single Bitrix24 CRM item through the TEST-specific origin pair:
`originatorId=MSP_ONEC_NEWBASE` and `originId=Ref_Key`. Then it performs
`crm.item.get` and verifies the CRM ID and original GUID.

For `LEGAL` / company (entity type 4), it requires name, full official
name and a 10- or 12-digit INN. It requires *exactly one* existing company
requisite with matching CRM ownership, type, and PRESET_ID=1. Missing or
ambiguous requisite matches are not silently created or picked by rank.
For `PERSON` / contact (entity type 3), it uses the source display name
as the CRM `name` field, consistent with the initial TEST import, but
refuses existing contacts with separately populated `secondName` or
`lastName`. It does not try to infer split names.

The dry-run only reports MATCH/DIFF, with no buyer names or INNs in the
output. The optional `-Apply` path is additionally guarded by an explicit
local approval file specifying *one GUID and one source generation*.
Nothing creates that file automatically, and `-Apply` is never scheduled.

On an explicitly authorized TEST write, the worker records an
`UPDATE_SENT` marker in SRV SQLite **before** Bitrix24 calls.
It independently submits only the necessary `crm.item.update` and
`crm.requisite.update` commands. It then calls the matching GETs again
and compares source values. It only clears the matching local
`UPDATE_REQUIRED` event when both the item and requisite backreads pass.
The exact outbox delete and a `changes() = 1` guard are in one SQLite
transaction. No blind retry after a transport ambiguity.

## Boundaries not yet accepted

- No installed PowerShell 2.0 runtime run on physical SRV.
- No completed real Bitrix24 item/requisite update with backread.
- No profile/ACL/pinned deployment of this worker; no automatic update tick.
- No field ownership policy for unrelated Bitrix24 edits. The only fields
  potentially overwritten are the name/title and verified company name,
  full name, and INN requisites. Other fields remain untouched.
- No phone/email sync, no classification change, no contact FIO splitting,
  no creation of missing requisites, no deletion, no migration to production.
- No monitoring/recovery operator workflow for the durable `UPDATE_SENT`
  marker after an uncertain transport result.
- Offline unit tests validate guardrails, mutation sequence, and
  synthetic SQLite acknowledgment; they do not yet simulate the full
  PowerShell+Bitrix transport end-to-end.

## Next safe acceptance

Run **only source-free offline tests** and native PowerShell 2.0 syntax
check before any SRV package. Next, prepare one explicitly designated
TEST buyer and the exact existing CRM match with read-only dry-run. Any
live CRM update is a separate gated action, not implied by PR or tests.

Reference:
https://apidocs.bitrix24.com/api-reference/crm/universal/crm-item-update.html
https://apidocs.bitrix24.com/api-reference/crm/requisites/universal/crm-requisite-update.html

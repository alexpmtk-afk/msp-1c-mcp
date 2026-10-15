# MSP Bitrix24 Bridge: counterparty mapping (schema gate 2026-10-15)

## Evidence
- Physical SRV, only TEST 1C NewBase OData, `$metadata` GET returned HTTP 200 and 1492 entity sets.
- `Catalog_Контрагенты`: key `Ref_Key` (Edm.Guid), 66 properties.
- `Catalog_Контрагенты_КонтактнаяИнформация`: compound key `Ref_Key` and `LineNumber`, 16 properties.
- Count-only check on SRV returned 7,635 counterparties, 6,770 buyer-flagged, and 6,433 active not-deleted buyers (15 Oct 2026). No customer rows were fetched, no Bitrix24 portal queried, no 1C writes.
- Full 65-page audited scan on SRV: 6,433/6,433 read, 6,433 unique GUIDs, no duplicates, PASS.
- Among active buyers: full name nonblank 5,577; INN nonblank 1,925; both nonblank 1,912.
- Missing full name 856; missing INN 4,508; either required field missing 4,521.
- INN containing exactly 10/12 ASCII digits 1,921 (4 nonempty values have another shape; checksum NOT validated).
- These results do NOT classify legal entities versus individuals; never treat the missing INNs as 4,508 faulty organizations.
- No source customer names, INNs or GUIDs were exported. No 1C writes or Bitrix REST calls.
- Actual field labels/types below were obtained from current 1C metadata, not assumed.

## Provisional mapping (Bitrix24 target NOT validated against portal yet)

| TEST 1C source | Bitrix24 candidate | Gate |
| --- | --- | --- |
| `Ref_Key` | company/contact `ORIGIN_ID` with stable `ORIGINATOR_ID` namespace | Portal integration identity and collision strategy pending |
| `НаименованиеПолное` | company `TITLE` (suggested visible title) | Must show complete name; verify display policy |
| `НаименованиеПолное` | requisite `RQ_COMPANY_FULL_NAME` | **Required for organizations**; validate requisite preset in portal |
| `ИНН` | requisite `RQ_INN` | **Required for organizations**; validate nonempty value and requisite preset |
| `Description` | optional company short name or requisite `RQ_COMPANY_NAME` | Secondary field; never replace full organization name |
| `КПП` | requisite `RQ_KPP` | Verified generic API field; company only if applicable |
| `КодПоОКПО` | requisite `RQ_OKPO` | Optional, verify applicability |
| `Покупатель` | eligibility gate, not a CRM field | Only buyer=true considered |
| `DeletionMark`, `Недействителен` | suppress new import; future lifecycle policy | Never auto-delete CRM records |
| `ЮридическоеФизическоеЛицо` | company versus contact decision | Enum values not yet inspected; do not infer |
| `ФИО` | contact `NAME`, `SECOND_NAME`, `LAST_NAME` | Splitting name is NOT validated; avoid automatic split |
| `DataVersion` | possible `ORIGIN_VERSION` | Only after verifying semantics |
| `КонтактнаяИнформация` | company/contact `PHONE`, `EMAIL` multi-fields | Interpret `Тип` and `Вид_Key` before mapping |

**Contact table**: composite identity `Ref_Key+LineNumber`; candidate content fields
`Тип`, `Вид_Key`, `Представление`, `Значение`, `АдресЭП`,
`НомерТелефона`, `Город`, `Регион`, `Страна`, `ДействуетС`.
No row content inspected, so email/phone/address subtype logic remains TBD.

### Required minimum, user-confirmed 15 Oct 2026

**Organization synchronization MUST include BOTH**:
1. `НаименованиеПолное` from 1C as Bitrix24 requisite `RQ_COMPANY_FULL_NAME` (and preferably visible company title `TITLE`).
2. `ИНН` from 1C as Bitrix24 requisite `RQ_INN`.

Bitrix API field `RQ_COMPANY_NAME` is **short** organization name; do not use it as the full name.
Full-name and INN completeness are release gates: no automatic write of organizations
with either field missing until a specific exception workflow is approved.
Complete locally verified audit: 1,912 of 6,433 active buyers had both fields
nonblank after whitespace trimming. The count covers ALL buyer types.
An OData string filter `НаименованиеПолное ne ''` caused HTTP 500;
a 65-page LOCAL-only scan is the accepted alternative for this test.
No inference about organization readiness is permitted before classifying
`ЮридическоеФизическоеЛицо`.

Not all counterparties are organizations. `ЮридическоеФизическоеЛицо` has
Edm.String type, but **actual values have not been checked**; natural persons
must receive a separate eligibility and field policy, never silently excluded
or converted to legal entities.

Source: https://apidocs.bitrix24.com/api-reference/crm/requisites/universal/crm-requisite-fields.html

### Scope and safety
- Ignore non-buyer-only suppliers by default; buyer=true and supplier=true is eligible unless business rules exclude it.
- Eligibility for initial analysis: `Покупатель eq true and DeletionMark eq false and Недействителен eq false`.
- Metadata confirms these properties exist; counts & actual flag values must be verified on TEST 1C.
- Existing CRM duplicates and matched external IDs must be reviewed before any write.
- Use TEST-specific origin namespace; never merge TEST identities into production without explicit mapping.
- `MspBitrix24Bridge` remains SAFE_IDLE with no Bitrix24 network requests.
- Preserve stable GUID on source identity; do not match solely by names or INN.
- `КонтактноеЛицо_Key` is only a link; not a proven standalone CRM contact.
- Do not transfer DOB, document identity info, or raw bank details during first phase.

Official documentation:
- https://apidocs.bitrix24.com/api-reference/crm/companies/crm-company-fields.html
- https://apidocs.bitrix24.com/api-reference/crm/contacts/crm-contact-fields.html
- https://apidocs.bitrix24.com/api-reference/crm/requisites/universal/crm-requisite-add.html
- https://apidocs.bitrix24.com/api-reference/crm/universal/object-fields.html
- 1C OData `$count` with `$filter`: https://1c-dn.com/download-trial/files/guides/developer_guide.pdf

## Next gate
Accepted: full 6,433-buyer local field-completeness scan and 6,433 unique GUIDs.
Next run `bin/pilot-buyer-types-local-100.ps1` manually on SRV to discover
distinct `ЮридическоеФизическоеЛицо` category values from a max-100-record
sample. The script outputs only category names/counters, not customer fields,
GUIDs or names. The sample is NOT a population estimate. Later evaluate
whether per-category aggregate OData counts work without re-scanning all 6,433.
No changes to system bridge or existing MSP tasks.

# MSP Bitrix24 Bridge: counterparty mapping (schema gate 2026-10-15)

## Evidence
- Physical SRV, only TEST 1C NewBase OData, `$metadata` GET returned HTTP 200 and 1492 entity sets.
- `Catalog_Контрагенты`: key `Ref_Key` (Edm.Guid), 66 properties.
- `Catalog_Контрагенты_КонтактнаяИнформация`: compound key `Ref_Key` and `LineNumber`, 16 properties.
- No customer rows were fetched, no Bitrix24 portal queried, no 1C writes.
- Actual field labels/types below were obtained from current 1C metadata, not assumed.

## Provisional mapping (Bitrix24 target NOT validated against portal yet)

| TEST 1C source | Bitrix24 candidate | Gate |
| --- | --- | --- |
| `Ref_Key` | company/contact `ORIGIN_ID` with stable `ORIGINATOR_ID` namespace | Portal integration identity and collision strategy pending |
| `Description` | company `TITLE` | Validate desired short-name policy |
| `НаименованиеПолное` | requisite `RQ_COMPANY_NAME` where available | Confirm portal and requisite preset |
| `ИНН` | requisite `RQ_INN` | Verified generic API field; need portal preset |
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
Execute `bin/inspect-customers-counts.ps1` manually on physical SRV using `MCP_OData_ReadOnly`.
Only returns three integer counts from TEST 1C using `$count`, no rows or identifiers.
No changes to system bridge or existing MSP tasks.

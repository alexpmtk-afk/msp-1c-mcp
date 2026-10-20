# 2026-10-15: full organization name OData comparison fails on SRV

Read-only OData count diagnostics:
- Baseline active buyers: 6,433 (HTTP 200)
- Filter `ИНН ne ''`: 1,925 (HTTP 200)
- Filter `НаименованиеПолное ne ''`: HTTP 500
- Combined query was intentionally skipped
- These are *test* 1C data; no Bitrix API calls or writes.

Likely cause (not yet proved from server error response): comparing an
unlimited-length string in 1C OData may cause HTTP 500. Never infer that
all 4,508 remaining buyers have invalid INN; null and whitespace handling
are not yet proven. Do not assume every buyer is a legal entity.

The next probe is deliberately capped at **10 rows**, only within physical
SRV and its local loopback OData test database. It reads `Ref_Key`,
`НаименованиеПолное`, `ИНН` into process memory with server-side Boolean
eligibility filter, GUID ordering and `$top=10`. A 1-MiB response limit,
HTTP status check and restricted Atom/XML parsing are enforced.
It produces only 10-row aggregated counts and failure codes; no
names, INNs, GUIDs, XML, URLs or credentials in output or files.
No full table scan until the pilot works. No changes to SAFE_IDLE task.

Evidence: OData v3 supports `$top`, `$select`, `$filter` and
`$orderby` independently of a string comparison.
See https://www.odata.org/documentation/odata-version-3-0/url-conventions/
See 1C examples at https://github.com/hacker-cb/1c-odata/blob/master/docs/1c/markdown/17.4_-_C%D1%82%D0%B0%D0%B4%D0%B4%D0%B0%D1%80%D1%82%D0%BD%D1%8B%D0%B9_%D0%B8%D0%BD%D1%82%D0%B5%D1%80%D1%84%D0%B5%D0%B9%D1%81_OData_8_3_27.md

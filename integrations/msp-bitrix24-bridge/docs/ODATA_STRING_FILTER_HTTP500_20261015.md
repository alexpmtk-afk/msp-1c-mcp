# 2026-10-15: isolated SRV OData 500 on required-field counts

Operator executed verified `inspect-customers-required-counts.ps1` and received
`RESULT=FAIL;STAGE=BITRIX24_REQUIRED_FIELD_COUNTS;GATE=HTTP_500`.
Earlier count-only test was successful:
- 7,635 counterparties, 6,770 flagged buyers, 6,433 active/not deleted.
- Customer entity metadata confirmed `НаименованиеПолное` and `ИНН` as Edm.String.
- No real customer rows were exported and no 1C writes or Bitrix API calls occurred.

**Hypothesis, not conclusion:** one OData v3 `$filter` string comparison
(`НаименованиеПолное ne ''` and/or `ИНН ne ''`) may be rejected by the
current 1C OData implementation; the existing script hid which call failed.
The previous boolean-filtered `$count` worked, so HTTP 500 alone
must not be diagnosed as authentication failure.

New tool: `bin/diagnose-customer-string-filters.ps1` is manually
executed on SRV, **not** under the scheduled bridge task. Only requests
`/$count` from test localhost 8085 using read-only 1C user. Executes:
1. Baseline known boolean filter
2. Full-name nonempty comparison, record HTTP status / numeric count only
3. INN nonempty comparison, record HTTP status / numeric count only
4. Combined only if 2 and 3 succeeded

Even on failures, never prints HTTP error response bodies, customer rows,
IDs, INNs, names or authentication details. Do not retry a failed
expression automatically. No writes/Bitrix calls and no changes to
`MspBitrix24Bridge` timers or SAFE_IDLE policy.

Once the individual failing comparison is known, implement compatible
read-only counting or a strictly local bounded streaming workaround,
without exposing customer data.

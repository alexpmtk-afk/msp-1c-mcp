# 2026-10-15: full read-only audit of required customer fields

10-row LOCAL-only pilot succeeded on SRV:
- HTTP=200, rows=10, 10 nonblank full names, 10 nonblank INN, 10 with both.
- No customer records or identifiers exported.
- Base `$count` active buyers=6433; standalone `ИНН ne ''` count=1925.
- OData string `НаименованиеПолное ne ''` returned HTTP 500; do NOT retry that predicate.

Manually execute `bin/scan-customers-required-fields.ps1`, pinned by SHA256,
only on authorized physical SRV. This is an offline-ish local TEST 1C data scan,
not Bitrix24 data sync and not part of the system task. Login prefilled,
password prompted securely in native PowerShell 2.0.

SAFETY GATES:
- localhost TEST OData only; GET, no redirects/proxy, authentication required.
- Server-side `Покупатель eq true and DeletionMark eq false and Недействителен eq false`.
- Select just Ref_Key, full name and INN; deterministic order Ref_Key asc;
  `$top=100` and `$skip=<processed>`, i.e. fetch bounded pages.
- Each response XML must be Atom feed; maximum 3 MiB response.
- Each GUID must be present and unique across *all* pages.
- Pre and post count of active buyers must both equal exactly 6433;
  if the test database changes, fail closed. Max 10000 rows or 150 pages.
- No external data export: names, INNs, IDs are processed only in process
  memory. No file writes. Output only aggregate counters/progress.
- A string is treated filled when `.Trim().Length > 0`.
- INN 10/12-digit *shape* is counted only, not checksum validity.
- Do not infer organizational form; buyer set can contain natural persons.

Completion requires ROWS_SCANNED=6433, UNIQUE_GUIDS=6433, PASS
and initial/final count unchanged. On any failure, do not re-run automatically.
No changes to SAFE_IDLE or schedule of `MspBitrix24Bridge`.

OData: documented `$top`, `$skip`, `$orderby` support in 1C 8.3
(see https://its.1c.eu/db/v8316doc/bookmark/dev/TI000001383).

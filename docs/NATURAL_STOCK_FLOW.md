# 1C NewBase: natural-language stock requests (implementation boundary)

Status as of **2026-10-16** (supersedes 15 October snapshots below): **VPS relay and scheduled SRV natural agent deployed; physically verified one-line PowerShell 2.0 stdout fix; real queue and native MCP exact-name lookup at named `Основной склад` PASS with two separate cards. Natural MCP wrapper flag enabled and Hermes default include-list updated. Unspecified/all-warehouse queries still fail `UNAVAILABLE`; substring matching, article live acceptance and Telegram conversational test remain PENDING.**

## Accepted user-facing requests

- `трн.02.034.9005.02.30 — какой остаток?` → exact 1C **article**, all accessible warehouses.
- `Сколько осталось комплекта «Мастер»?` → exact 1C **name**, all accessible warehouses.
- `Остаток артикула ТРН-123 на Основном складе?` → exact 1C article plus **real warehouse name**.
- `Найди [название] на складе «Готовая продукция»` → exact 1C name plus real warehouse name.

A user is **never asked for product/warehouse GUIDs** and the 1C internal Code (`НФ-...`) is **not a search mode**. Users search ONLY by published article (`Артикул`) or product name (`Description`). An internal Code is displayed only to distinguish two cards, even if their article fields are blank. **Return all matching cards, each with its own warehouse balances; never choose one card or combine their totals.** Missing Balance row may be displayed as a qualified `0` per the reporting preference, but must be marked `NO_BALANCE_ROW` and never claimed as an observed zero record.

## Flow / trust boundaries

1. Telegram / Hermes parses only `article` or `name`, plus optional `warehouse_name`. Duplicate matching cards are **all shown** (1, 2, 10, ...), not resolved by forcing a code-based re-query.
2. The staged (currently disabled) read-only MCP tool passes only this typed request to the existing localhost VPS relay. An exact Unicode NFC wire contract is implemented in `natural_stock_contract.py`. No user-supplied OData URL, filter, SQL, arbitrary command, GUID, or credentials.
3. The VPS relay has the restricted natural job type deployed, together with the fixed agent-only ingress path (private GitHub owner-gated installation Issues #411/#412: PASS). The existing GUID-based `STOCK|guid|guid` operation remains in service; old-route regression Issue #415: PASS. **Do not enqueue new natural jobs until the physical SRV handler is accepted and installed.**
4. On SRV Windows Server 2008 R2, the existing LocalService identity reads *only* the fixed `NewBase` OData site, using the already enrolled `MCP_OData_ReadOnly` credential. Resolve **all** item catalog entries matching the chosen article/name to their internal `Ref_Key` values. The human warehouse title resolves in `Catalog_СтруктурныеЕдиницы.Description` (confirmed by SRV live tests); it is a mixed structural-unit catalog and not all entries are physical warehouses.
5. For **every** matched item, execute the fixed `AccumulationRegister_ЗапасыНаСкладах/Balance(Dimensions='Номенклатура,СтруктурнаяЕдиница')` query with its authoritative item reference, and the selected warehouse/all warehouses. Fully verify bounded results and pagination before reporting. The pure `natural_stock_resolution.py` returns all matching items separately with per-item Decimal quantities, never an aggregate across distinct item cards. No silent truncation.
6. MCP should return for **each** catalog match: name, published article (or `не указан`), 1C Code for identification only, requested warehouse and stock, or per-warehouse quantities. It should mark missing Balance rows as `NO_BALANCE_ROW` and display `0` only with that qualifier. No GUIDs/secrets and no cross-card total.

## Mandatory gates before enabling in Hermes

- **A / schema:** Run the read-only `onec-natural-stock-schema-preflight.ps1` on **SRV under LocalService**, via separately approved version-controlled integration. It does not touch the scheduled agent by itself. Confirm exact OData article/name and warehouse entity fields, and example article match cardinality. CI syntax validation is **not** a live SRV execution.
- **B / OData:** Prove bounded item/warehouse exact name filters under the real read-only account, including escaping `'` to OData `''`, Unicode, duplicate matches, null balances, paging limits, multiple warehouses and permission failures.
- **C / fixed queue — PASS:** Multi-card name/article protocol, bounded result receipt and agent-only ingress deployed on VPS in separate owner-gated steps; original GUID handler regression checked. Hermes new tool remains disabled.
- **D / controlled SRV installation — PARTIAL:** On physical SRV, a read-only, triggerless LocalService **V3 diagnostic** returned `STAGE=COMPLETED; REASON=NONE; ERROR_TYPE=NONE; RESULT=PASS`; existing poller remained unchanged and temporary task cleaned. This is **not** yet the explicit separate two-card/6/qualified-0 acceptance required before cutover. Two earlier complete installer attempts stopped at smoke and restored the old agent; their failures are not treated as installation successes. A fresh reviewed, SHA-pinned, authorized update with rollback is still required. The existing nonadmin personal account must **never** be elevated or added to administrators.
- **E / acceptance — PENDING:** Only after D passes, verify a fresh authorized natural queue job with both exact-name cards and separate 6 / qualified no-row zero at the named warehouse. Then conditionally enable the native MCP tool and verify an actual read-only tool call, followed by a Hermes/Telegram turn when its usage limit is available. Old `onec_stock_by_guid` must remain accepted. No 1C writes or general Hermes Gateway restarts.

## Explicit result states

| State | Meaning |
|---|---|
| `PASS` with total quantity `0` | Real, independently verified OData zero balance row |
| `ITEM_NOT_FOUND` | No matching 1C article / name |
| `PASS` with `match_count` > 1 | Every matching 1C catalog card is listed separately, with its own stock; no artificial ambiguity blocker |
| `WAREHOUSE_NOT_FOUND` | No exact warehouse name found |
| `WAREHOUSE_AMBIGUOUS` | Multiple warehouse records share that name |
| `NO_BALANCE_ROW` per card | Missing Balance row; qualified display `0 (запись отсутствует)`, **not** an observed zero |
| `*_RESULT_INCOMPLETE` | Capped/paged/unverified query; no partial quantity returned |
| `UNAVAILABLE` / transport failure | Cannot determine quantity; never invent a value |

Existing `onec_stock_by_guid` remains unchanged. The name/article semantics are implemented and offline-tested, but **a description of deployed exact-name + selected-warehouse MCP capability only; natural all-warehouse and substring user requests remain unaccepted**.


## Live NewBase evidence: duplicate product names (15 Oct 2026)

Authenticated GET from physical SRV confirmed exact name `Слэмбол 6 кг` matches
**two** catalog cards. Exact warehouse `Основной склад` matches one
structural-unit card:

| 1C Code | Published article | Existing Balance row at «Основной склад» |
|---|---|---|
| `НФ-00001359` | Blank | Verified quantity `6` |
| `НФ-00000879` | Blank | `NO_BALANCE_ROW` — **not zero** |

A successful read-only verification established both catalog entries.
For `name` the updated offline resolution returns **both** cards in one result:
`НФ-00001359` — **6** on `Основной склад`; `НФ-00000879` —
**0 (no Balance row)**. Codes are display-only metadata; there is no
`LOOKUP1|code` request mode, no need for a follow-up selection, and no
GUIDs in user-facing results. Search by published article must follow the
same all-matches rule when multiple catalog items share an article.

Also confirmed `Catalog_СтруктурныеЕдиницы` has mixed structural units
(warehouses, office, people, subdivisions). Do not infer a physical warehouse
solely from its name. The actual read-only balance URL uses the route
`AccumulationRegister_ЗапасыНаСкладах/Balance(Dimensions='Номенклатура,СтруктурнаяЕдиница')`.
The earlier schema probe was incorrect to search for a separate
`AccumulationRegister_ЗапасыНаСкладахBalance` EntityType.

**Status boundary (updated 15 October):** The early item/warehouse/stock lookups were made manually on physical SRV under the restricted read-only 1C user. Subsequently, VPS `LOOKUP1|article|...` / `LOOKUP1|name|...` relay and protected agent-only ingress were **deployed**, with backward-compatible probe PASS. The V3 LocalService diagnostic verified successful read and response serialization from test NewBase. As of that historical 15 October checkpoint the scheduled handler and natural E2E were still pending; see the **16 October acceptance and remaining blockers** section below.


## Bounded enumeration and cardinality

- 0 matching products: `ITEM_NOT_FOUND`.
- 1 product: one card and that card's own stock.
- 2 or 10 products: every card and its own stock/warehouse rows, even if article or name is duplicated.
- Up to 50 products: independently return all verified matches. The 51st item is an explicit `ITEM_RESULT_INCOMPLETE`, **not** a 50-row partial answer.
- Current offline parser can accept up to 2,500 item/warehouse balance records; excess or OData continuation that has not been followed triggers `BALANCE_RESULT_INCOMPLETE`.
- Actual server-side GET, pagination and relay support for this larger result set are not yet deployed. Do not claim live Hermes support until end-to-end acceptance.

## Last physical SRV diagnostic and current no-quota boundary (15 October 2026)

At the historical 15 October checkpoint the user supplied the following **actual** physical SRV result from the V3 prefetched, pinned, read-only LocalService diagnostic:

```text
STAGE=COMPLETED
REASON=NONE
ERROR_TYPE=NONE
RESULT=PASS
OPERATING_AGENT_UNCHANGED=YES
TEMPORARY_TASK_CLEANUP=PASS
```

This supports only completion of the local read-only flow through final JSON serialization. **It does not independently certify** that the first code has 6 and the second code has a missing Balance row: a **separate two-card assertion** in the fixed manual smoke script is still pending on physical SRV. Do not repeat legacy V1/V2 cutover scripts or assume success from green offline CI.

The Hermes agent's user-facing quota was temporarily exhausted. Consequently, do not rely on or attempt a Hermes-initiated natural-stock request before that quota refreshes. The following can be prepared without Hermes usage: review the PS2 fixed source/rollback gates, verify SHA-pinned artifacts, run offline GitHub CI and document the acceptance conditions. **Do not represent a source commit or GitHub CI as live SRV deployment.**

Required remaining sequence: approved **triggerless** LocalService exact-name/two-card acceptance → carefully controlled scheduled-agent cutover with backup and automatic heartbeat → fresh real VPS→SRV→1C→VPS natural queue receipt → opt-in native MCP acceptance → Hermes/Telegram verification after quota recovery.

## 16 October 2026 — superseding live SRV/VPS/Hermes acceptance

**Confirmed physical WinServer2008R2 / PowerShell2 stdout failure and remedy.** Nested `powershell.exe -File` output captured by the parent poller split a long `Write-Output ('NAT_'+$encoded)` string into multiple physical lines (e.g. 1000 `A` characters became 9 lines, with verified lossless concatenation). The parent fixed protocol deliberately rejected any output that was not exactly one `NAT_<base64url-json>` line and stored `UNAVAILABLE`. The source-only single-line correction was to replace the emitter with `[Console]::Out.WriteLine(('NAT_'+$encoded))`. Physical SRV comparison of 1000 characters proved `LINES=1`; no parent validation bypass or 1C data write was introduced. Physical SHA/Git evidence for patched helper: blob `23122be18ed522f7d281cb19d897e2d37748024f`, SHA256 `c287889b2a9e7600f659bb3346f5a2638a100d8a6413a7438caac445fae760e0`. Original helper was blob `08c23d0d6316ba7ddf1fd3e0f62e3269314838c7`; the parent poller stayed `006a0b618575b4ab3a00b54c2863a436841e00ed`. A backup of the original helper exists on SRV. The **public branch now matches the installed patched helper byte-for-byte**, with a source/output regression test in CI.

**Real accepted, read-only E2E scoped to named warehouse:** after a successful LocalService `CHILD_EXIT_ZERO=YES; STDOUT_COUNT=1; NAT_COUNT=1; NAT_STATUS=PASS`, a fresh VPS natural-stock job returned `done/NATURAL_RESULT`, and the stored payload readback matched the MCP client response. Exact name `Слэмбол 6 кг`, warehouse `Основной склад`, returned two distinct cards: internal code `НФ-00001359` quantity `6` with `HAS_BALANCE_ROWS`; internal code `НФ-00000879` quantity represented as `0` with `NO_BALANCE_ROW`. Blank articles are `null`. A subsequent **fresh native STDIO MCP tools/call** using the same request returned PASS as well; existing GUID tool is still discoverable. The wrapper now exports `ONEC_ENABLE_NATURAL_STOCK=1` with the prior selected-stock export preserved and a rollback backup retained. Hermes default config's `mcp_servers.onec_stock.tools.include` was updated through the normal CLI to allow both `onec_stock_by_guid` and `onec_stock_by_name_or_article`. Gateway was not restarted. **No Telegram/Hermes conversational call is claimed**; an existing session might require `/reload-mcp`.

**Known failing user scenario (do not reinterpret as zero):** exact name `Чехол на ракетку падел мягкий` with no warehouse → `UNAVAILABLE`; exact same name with `Основной склад` → one card, article `UW-2827`, internal code `НФ-00004720`, `0 / NO_BALANCE_ROW` **on that one warehouse only**. Exact `Слэмбол 6 кг` without a warehouse also → `UNAVAILABLE`, so the all-warehouse failure is general. The user's 1C screenshot shows a `Свободно` value 20 for the `UW-2827` main card; neither which structural unit holds the stock nor whether `Свободно` equals the chosen OData `Balance` measure has been proven. Do **not** report overall stock 0 or 20 without reconciling actual query scope and measures.

**Incomplete search behavior:** live helper currently uses the `Description eq '...'` OData filter and exact `-cne` check. Substring name search has **not** been implemented. Searches must return all independently matching physical and nonphysical catalog cards with their real names, published articles and type/role when known. The visible seven name-containing rows on the 1C screenshot appear to include manufacturing steps/expenses, but their actual types have not yet been independently retrieved. Do not sum them into the finished physical good. Changes to substring search must update OData query, postfilter, safe caps/pagination, protocol, MCP description, and tests **as one coherent block**; don't silently truncate after 50.

**Current all-warehouse diagnostic (unresolved):** a separate bounded, read-only `onec-system-odata-natural-investigation.ps1` was staged on the SRV with an allowlisted stage/reason/type receipt. An isolated LocalService probe with the fixed name `Чехол на ракетку падел мягкий` and `WarehouseB64='-'` produced `STDOUT_COUNT=5; NAT_COUNT=0` with diagnostic-like lines; no safe reason/type receipt had been retrieved at handoff. The simple `param([string]$WarehouseB64)` test accepted `'-'`, so **do not assert a dash parsing root cause** without testing the full helper signature. The current user's next safe gate is invocation of the separate investigation script under their non-LocalService account, where the expected `WRONG_IDENTITY` occurs before any OData access, revealing only safe startup/binding error information if one exists. The investigation copy, not the active helper, should be used for diagnostics. Treat that step as pending until its actual output is received.

**Limits of verification:** the full handoff and local-only materials are archived in a private repo review branch; private REMOTE files must be read under authorized ownership. No claim of article query live acceptance or native Telegram message handling. Production/test 1C writing is disabled; prior tool `onec_stock_by_guid` remains unaffected. Do not rerun V1–V4 obsolete installers or replace the corrected helper with a pinned old SHA.

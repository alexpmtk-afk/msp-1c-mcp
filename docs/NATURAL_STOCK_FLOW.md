# 1C NewBase: natural-language stock requests (implementation boundary)

Status: **SCHEMA PREFLIGHT + OFFLINE REQUEST/RESOLUTION LOGIC; NOT YET DEPLOYED** (2026-10-15).

## Accepted user-facing requests

- `трн.02.034.9005.02.30 — какой остаток?` → exact 1C **article**, all accessible warehouses.
- `Сколько осталось комплекта «Мастер»?` → exact 1C **name**, all accessible warehouses.
- `Остаток артикула ТРН-123 на Основном складе?` → exact 1C article plus **real warehouse name**.
- `Найди [название] на складе «Готовая продукция»` → exact 1C name plus real warehouse name.

A user is **never asked for product/warehouse GUIDs** and the 1C internal Code (`НФ-...`) is **not a search mode**. Users search ONLY by published article (`Артикул`) or product name (`Description`). An internal Code is displayed only to distinguish two cards, even if their article fields are blank. **Return all matching cards, each with its own warehouse balances; never choose one card or combine their totals.** Missing Balance row may be displayed as a qualified `0` per the reporting preference, but must be marked `NO_BALANCE_ROW` and never claimed as an observed zero record.

## Flow / trust boundaries

1. Telegram / Hermes parses only `article` or `name`, plus optional `warehouse_name`. Duplicate matching cards are **all shown** (1, 2, 10, ...), not resolved by forcing a code-based re-query.
2. One future read-only MCP tool passes only this typed request to the existing localhost VPS relay. An exact Unicode NFC wire contract is implemented in `natural_stock_contract.py`. No user-supplied OData URL, filter, SQL, arbitrary command, GUID, or credentials.
3. The VPS relay creates a restricted new job type for the NewBase read-only system poller. **Current production relay does NOT yet support this type.** The existing GUID-based `STOCK|guid|guid` operation must remain unchanged.
4. On SRV Windows Server 2008 R2, the existing LocalService identity reads *only* the fixed `NewBase` OData site, using the already enrolled `MCP_OData_ReadOnly` credential. Resolve **all** item catalog entries matching the chosen article/name to their internal `Ref_Key` values. The human warehouse title resolves in `Catalog_СтруктурныеЕдиницы.Description` (confirmed by SRV live tests); it is a mixed structural-unit catalog and not all entries are physical warehouses.
5. For **every** matched item, execute the fixed `AccumulationRegister_ЗапасыНаСкладах/Balance(Dimensions='Номенклатура,СтруктурнаяЕдиница')` query with its authoritative item reference, and the selected warehouse/all warehouses. Fully verify bounded results and pagination before reporting. The pure `natural_stock_resolution.py` returns all matching items separately with per-item Decimal quantities, never an aggregate across distinct item cards. No silent truncation.
6. MCP should return for **each** catalog match: name, published article (or `не указан`), 1C Code for identification only, requested warehouse and stock, or per-warehouse quantities. It should mark missing Balance rows as `NO_BALANCE_ROW` and display `0` only with that qualifier. No GUIDs/secrets and no cross-card total.

## Mandatory gates before enabling in Hermes

- **A / schema:** Run the read-only `onec-natural-stock-schema-preflight.ps1` on **SRV under LocalService**, via separately approved version-controlled integration. It does not touch the scheduled agent by itself. Confirm exact OData article/name and warehouse entity fields, and example article match cardinality. CI syntax validation is **not** a live SRV execution.
- **B / OData:** Prove bounded item/warehouse exact name filters under the real read-only account, including escaping `'` to OData `''`, Unicode, duplicate matches, null balances, paging limits, multiple warehouses and permission failures.
- **C / fixed queue:** Implement and offline-test the explicit new mode and Unicode-safe transport, result receipt and allowlisted error classes, without permitting arbitrary requests. Keep existing GUID jobs regression green. Do not release agent without a versioned rollback plan.
- **D / controlled SRV installation:** A separately authorized Windows system task update is required to add the fixed handler. The operator `SRV\parshin` is **not an administrator**. Do not ask them to run elevated commands or enable the retired WinRM Windows runner. Check approved deployment/access boundary; if unavailable, report `BLOCKED`.
- **E / acceptance:** Verify new full chain with a real article and human warehouse name, fresh queue job and matching OData data. Then verify a real Telegram-initiated Hermes turn. Old `onec_stock_by_guid` must remain accepted and available. No 1C writes, no Hermes Gateway or other MCP restarts.

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

Existing `onec_stock_by_guid` remains unchanged. These are target semantics and offline-verified logic, **not a claim that live article/name lookup already works**.


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

**Status boundary:** all of these item/warehouse/stock lookups were made
manually from SRV with the restricted read-only 1C user. Updated
`LOOKUP1|article|...` / `LOOKUP1|name|...` and multi-match resolution are **offline**,
pending approved new queue mode, agent handler and Hermes end-to-end test.


## Bounded enumeration and cardinality

- 0 matching products: `ITEM_NOT_FOUND`.
- 1 product: one card and that card's own stock.
- 2 or 10 products: every card and its own stock/warehouse rows, even if article or name is duplicated.
- Up to 50 products: independently return all verified matches. The 51st item is an explicit `ITEM_RESULT_INCOMPLETE`, **not** a 50-row partial answer.
- Current offline parser can accept up to 2,500 item/warehouse balance records; excess or OData continuation that has not been followed triggers `BALANCE_RESULT_INCOMPLETE`.
- Actual server-side GET, pagination and relay support for this larger result set are not yet deployed. Do not claim live Hermes support until end-to-end acceptance.

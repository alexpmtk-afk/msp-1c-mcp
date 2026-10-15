# 1C NewBase: natural-language stock requests (implementation boundary)

Status: **SCHEMA PREFLIGHT + OFFLINE REQUEST/RESOLUTION LOGIC; NOT YET DEPLOYED** (2026-10-15).

## Accepted user-facing requests

- `трн.02.034.9005.02.30 — какой остаток?` → exact 1C **article**, all accessible warehouses.
- `Сколько осталось комплекта «Мастер»?` → exact 1C **name**, all accessible warehouses.
- `Остаток артикула ТРН-123 на Основном складе?` → exact 1C article plus **real warehouse name**.
- `Найди [название] на складе «Готовая продукция»` → exact 1C name plus real warehouse name.

A user is **never asked for product/warehouse GUIDs**. Model must not hallucinate a match, use a third-party stock database as 1C, or convert a missing balance row into numerical zero.

## Flow / trust boundaries

1. Telegram / Hermes parses text into one of two explicit modes: `article` or `name`, plus optional `warehouse_name`. Ambiguity is clarified, not silently guessed.
2. One future read-only MCP tool passes only this typed request to the existing localhost VPS relay. An exact Unicode NFC wire contract is implemented in `natural_stock_contract.py`. No user-supplied OData URL, filter, SQL, arbitrary command, GUID, or credentials.
3. The VPS relay creates a restricted new job type for the NewBase read-only system poller. **Current production relay does NOT yet support this type.** The existing GUID-based `STOCK|guid|guid` operation must remain unchanged.
4. On SRV Windows Server 2008 R2, the existing LocalService identity reads *only* the fixed `NewBase` OData site, using the already enrolled `MCP_OData_ReadOnly` credential. First resolve the 1C item entity and exact article/name field into `Ref_Key`. Resolve real warehouse name to its authoritative 1C reference (the warehouse catalog name is **pending live metadata verification**).
5. Execute the fixed Balance request for the resolved item and selected warehouse or all warehouses. Obtain complete, bounded results, map warehouse GUIDs to actual names on the trusted side, then return only the authorized display fields and quantities. The pure `natural_stock_resolution.py` implements exact matching, ambiguity/error handling, Decimal summation and refusal to return partial results.
6. MCP returns product name, article, warehouse name(s), quantities and total, with provenance `1C NewBase Balance`. Telegram reports that naturally. GUIDs and secrets are not normally exposed to the user.

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
| `ITEM_AMBIGUOUS` | Multiple 1C products share the requested identifier |
| `WAREHOUSE_NOT_FOUND` | No exact warehouse name found |
| `WAREHOUSE_AMBIGUOUS` | Multiple warehouse records share that name |
| `NO_BALANCE_ROW` | No OData Balance row; **not equivalent to zero** |
| `*_RESULT_INCOMPLETE` | Capped/paged/unverified query; no partial quantity returned |
| `UNAVAILABLE` / transport failure | Cannot determine quantity; never invent a value |

Existing `onec_stock_by_guid` remains unchanged. These are target semantics and offline-verified logic, **not a claim that live article/name lookup already works**.

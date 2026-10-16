# 1C NewBase natural stock — final physical SRV/VPS handoff (16 Oct 2026)

**Status:** physically validated specific-warehouse and ALL-warehouses exact-name/exact-business-article **read-only** lookups; partial-name matching **NOT IMPLEMENTED**; Hermes/Telegram conversational 1C invocation **NOT TESTED**.

This is a sanitized, source-controlled digest of the owner's `TECHNICAL_HANDOFF_FINAL_2026-10-16.md`. The physical SRV PowerShell 2.0 evidence and fresh queue/STDIO MCP checks were performed by Hermes with user-assisted SRV execution and reported by Hermes. Updating GitHub source does **not** redeploy SRV files. Do not infer live 1C access from CI.

## What was fixed on physical Windows Server 2008 R2 / PowerShell 2.0

1. Child process `Write-Output ('NAT_'+$encoded)` wrapped a 1,000-character string into 9 physical lines (119×8 + 48) when consumed from the parent PowerShell process. `[Console]::Out.WriteLine(('NAT_'+$encoded))` produced exactly one 1,000-character line. Preserve the parent's **single-NAT-envelope strict validation**; never accept arbitrary extra lines or silently concatenate them.
2. External LOOKUP1 uses the sentinel `-` for an unspecified warehouse. Passing that literal as the argument to child `-WarehouseB64 -` with the child's `[Parameter(Mandatory=$true)][string]$WarehouseB64` caused argument binding/usage output on the physical PS2 host instead of handler execution, with exit code potentially 0. Map **only** the absent-warehouse sentinel to `ALL` at the poller→child boundary. Child treats `ALL` as no warehouse restriction. Real encoded warehouse names (including base64url `-`) remain unmodified.

**Current source pins (the exact Git blob SHA1 matches the Hermes handoff's prepared live SRV copies):**

| File | Expected Git blob SHA1 | Prepared source SHA256 |
|---|---|---|
| `scripts/windows/onec-system-odata-natural.ps1` | `2d592a8c74744dd1ebe07cab3cac2061866533ba` | `8d1b769bea2525ea89ffe7707c231e2434b189277aca7c5b60f20145d1a9f54c` |
| `scripts/windows/onec-system-probe-poll.ps1` | `1b36b1cbc726889ecc5228277280ef0399d2ed96` | `716555ed409294da8508ac28ef0258fee6cb57891b9db5c5f97c8941712276c3` |

The SHA256 values above are copied from the physical handoff, **not independently measured on SRV by this GitHub update**. Blob SHA1 values were independently confirmed against GitHub after the source updates. Existing installed SRV files were already updated and accepted by the Hermes workflow; no installer should overwrite them without re-reading current on-disk hashes.

## Accepted fresh read-only results (from final handoff)

| Scope | Result | Evidence |
|---|---|---|
| Exact name `Слэмбол 6 кг`, explicit `Основной склад` | Two separate 1C cards: `НФ-00001359` = 6 units from Balance row; `НФ-00000879` = displayed 0 with `NO_BALANCE_ROW` | New job `done/NATURAL_RESULT`, SQLite result readback matched |
| Exact name `Чехол на ракетку падел мягкий`, no warehouse | One card `UW-2827` / `НФ-00004720`, 20 units on **`Основной склад ИП Новокшенов`**; `Основной склад` is a different structural-unit record, where there was no balance row | New job created 2026-10-16 10:21:40 UTC, `PASS`, SQLite exact saved JSON matched |
| Exact article `UW-2827`, all warehouses through installed STDIO MCP | One card, 20 units on `Основной склад ИП Новокшенов` | Fresh job at 10:49:24 UTC; `isError=false`, exact SQLite readback |
| Exact name `Слэмбол 6 кг`, all warehouses through installed STDIO MCP | Two cards, separate quantities 6 and qualified 0 (`NO_BALANCE_ROW`) | Fresh job at 10:50:24 UTC; `isError=false`, exact SQLite readback |

Both STDIO checks discovered `onec_stock_by_guid` and `onec_stock_by_name_or_article`; default Hermes `mcp_servers.onec_stock.tools.include` includes both, wrapper exports `ONEC_ENABLE_NATURAL_STOCK=1`. Confirmed `queue.sqlite` `quick_check=ok`, 34 completed jobs, no pending/leased at handoff. Tests were run against **test NewBase** only; no source business changes, no OData write, no production base migration.

**Earlier `UNAVAILABLE` records are historical failures, not a correct zero-stock result.** Two isolated post-patch requests also temporarily failed before fresh passes; their distinct causes were not established, so do not claim eventual consistency, cache or restart causes.

## Remaining requirements and acceptance gates

- **Partial-name search** is NOT supported: installed OData filter is `Description eq` and server code also checks exact name; substring phrase matching must be implemented consistently in filter, post-filter, MCP tool description and tests. Result limits: 50 item cards, 50 warehouse rows per card; an incomplete selection must never be presented as exhaustive.
- **Original issue example** `трн.02.034.9005.02.30` has not been individually proven by a fresh live article lookup. The `UW-2827` article test proves that the **article mode works for that tested SKU**, not the originally named sample. Keep its item-specific gate open.
- **Hermes conversational request to 1C from Telegram** was not tested in this handoff. A successful native STDIO tool call is not proof of a conversational MCP invocation.
- `Свободно` in 1C GUI equalled 20 for this one tested card. It is not proven generally equivalent to total `КоличествоBalance` because reservations and filters have not been independently checked.
- Physical SRV administrative rights are separate from `SRV\\parshin`, who must not be asked to join local Administrators. Keep all updates approved, narrowly pinned, read-only with backup/rollback.
- Avoid production 1C, arbitrary URLs, executable commands through queue, changing HTTP protocol or weakening access. No new source code may be assumed installed automatically.

## Source and deployment discipline

- Preserve the current pair of SRV files together. Do not run older V1–V4 installed-child probes, old cutover scripts or legacy pins as a "clean-up": those are historical and may reject current state or overwrite it.
- Historical probes may retain immutable source pins for their **historical** installation scenarios. To verify current build, use these updated source pins and a dedicated non-mutating check; do not repin old installation histories to claim a new deployment.
- `tests/windows/test_onec_natural_stdout_contract.ps1` and `tests/windows/test_onec_natural_all_warehouses_contract.ps1` enforce current source contracts on Windows CI. These modern-host tests do **not** reproduce the physical Win2008R2 PS2 format/binding behavior; physical measurements are in the handoff.
- Confirm future source pin and SHA256 from installed file before changing any SRV agent; preserve backup files `.before-stdout-fix` and `.before-all-warehouses-fix`, rather than rolling back working behavior.

Source review: draft PR #16; long-running original requirement: Issue #15; private diagnostic history: `msp-server-bridge` Issues #428 and PR #429.

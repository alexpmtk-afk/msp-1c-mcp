# MSP Bitrix24 Bridge

**Project:** msp-bitrix24-bridge  
**Target host:** physical SRV, Windows Server 2008 R2, PowerShell 2.0  
**Runtime location:** C:\ProgramData\MspBitrix24Bridge  
**Windows identity:** NT AUTHORITY\LOCAL SERVICE (SID S-1-5-19)

This is a **standalone staged integration module** for Bitrix24 <-> 1C. It does not use the GitHub, VPS or Hermes transport at runtime. Source control can remain in GitHub; runtime cannot.

## Stage A (this PR)

- Machine-level program files, ACLs, separate Task Scheduler task.
- Boot trigger and periodic retry every five minutes, no interactive user logon.
- Default **SAFE_IDLE** mode: never contacts Bitrix24 or 1C, sends no personal data, and makes no data changes.
- Read-only, interactive metadata inventory of TEST NewBase using the existing loopback IIS/OData publication.
- Strictly separate future capabilities: customers.read, products.read, invoices.create.
- No dynamic commands, no arbitrary remote URLs, no executable scripts fetched at runtime.

## State, scope, and acceptance gates

| Gate | State |
| --- | --- |
| Offline source tests | Required |
| Native Windows Server 2008 R2 / PowerShell 2 parse | NOT YET TESTED |
| LocalService boot/start-up task | NOT YET INSTALLED |
| Authenticated OData customer object inventory | NOT YET TESTED |
| Bitrix24 authorization | NOT YET CONFIGURED |
| Customer sync | DISABLED / NOT IMPLEMENTED |
| Create invoices / any 1C write | DISABLED / NOT IMPLEMENTED |

Only sandbox D:\DATA\NewBase is in scope for OData inspection. The production 1C infobase is not part of this phase.

## Operator workflow

1. Review scripts before downloading to SRV and approve a pinned source revision/hash.
2. Run bin\preflight.ps1 on SRV (read-only).
3. Run bin\inspect-customers-metadata.ps1 on SRV using a locally entered 1C read-only credential; only entity-set names/count are returned, not customer records.
4. In a separate approved installation window, stage this entire folder locally on SRV and invoke bin\install-system.ps1.
5. Check bin\status.ps1, log out of RDP, then check again. Reboot acceptance is separate.
6. Add Bitrix24 REST credentials and exact customer field mapping **in a future gated PR** before any live sync.

**Do not mistake successful staging/heartbeat for working customer synchronization.**

## Planned extension points

- customers.read: explicit OData catalog + field mapping, bounded pages, deduplicated transfer to Bitrix24.
- products.read: separate mapping, rate control.
- invoices.create: separate dedicated 1C account, allowlisted document creation and readback, idempotency key, explicit test/production authorization, no automatic posting.

Both OData and Bitrix24 credentials must be stored only in machine-local protected storage. Do not put customer names, passwords, tokens, webhook URLs or raw replies in logs or GitHub.

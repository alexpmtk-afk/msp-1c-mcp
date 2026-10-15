# msp-bitrix24-bridge — isolation and future operations

1C UNF -- localhost IIS/OData --> independent Bitrix24 bridge (SRV) -- outbound HTTPS --> Bitrix24.
Existing MSP LocalService agent -- outbound HTTPS --> Tailscale Funnel/VPS/GitHub is a DIFFERENT branch.

At runtime the bridge:
- MUST NOT call GitHub, VPS, Hermes or the existing MSP queue.
- MUST NOT accept inbound network requests from Bitrix24.
- MUST run without RDP login: Task Scheduler, LocalService, boot + recurring trigger.
- MUST persist secrets in its own machine DPAPI container with ACL allowing only the operator and LocalService.
- MUST keep data and logs out of public source control.
- MUST start fail closed, read-only and disconnected.

Future registry (not yet activated):
* customers.read / customers.export: 1C catalog confirmed from real $metadata; stable GUID mapping; explicit subset fields; pagination; deduplication in Bitrix24; outbound-only REST with least-privilege webhook; opt-in before personal data transfer.
* products.read / products.export: independent catalog mapping; same bounds.
* invoices.create: separate write-scoped 1C principal, exact document schema, confirm/approve, replay key, status read-back, no posting without separate permission; production activation is independently gated.

System task is not a permanently resident background process. It is a machine-owned periodic scheduled task that starts automatically at boot, and operates without anyone logged in. Future code can be moved to a modern internal host without changing transport.

This first version only creates a SAFE_IDLE heartbeat and a local operator metadata inventory; it does not import customers.

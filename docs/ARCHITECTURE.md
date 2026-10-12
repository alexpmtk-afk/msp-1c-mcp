# Architecture — initial design

## Research track (NO Hermes dependency)

ChatGPT -> existing private `alexpmtk-afk/msp-server-bridge` -> GitHub Actions
-> approved self-hosted REMOTE runner action -> `msp-onec probe` -> secure network
-> published 1C OData `$metadata` -> bounded result -> GitHub -> ChatGPT.

**Not implemented:** a bridge allowlist entry and workflow for `onec-metadata-probe`, an
approved network path to the real 1C instance, user credentials and OData publication.
No live 1C access is claimed.

## Runtime track (later)

Hermes/Codex -> deployed `msp-1c-mcp` -> specialized tools -> 1C.
The public `msp-server-stack` is the canonical infrastructure inventory, while this
repository is canonical for the 1C integration code and semantic descriptions.
Do not copy tokens or full production datasets between repos.

## API strategy

1. Inspect standard OData `$metadata` and entity names.
2. Verify the actual UNF names, registers, dimensions and business rules.
3. Use OData for verified safe reads, then assess whether dedicated 1C HTTP services
   are necessary for complex document behavior (posting, filling tables, checks).
4. Do not assume posting an OData object runs the same form logic as an operator's
   actions in the UI; validate all resulting movements and status in a TEST infobase.
5. Promote each accepted instrument with typed arguments, business semantics,
   idempotency, permissions and acceptance tests.

## Environment separation

- HOME or actual 1C host: database and possibly HTTPS publication on a private interface.
- REMOTE `/opt/mcp/projects/`: future checkout, read-only probes, and final MCP runtime.
- REMOTE `/opt/mcp/secrets/`: credentials managed out-of-band (access-controlled).
- GitHub: source, workflows, fixtures and redacted verification reports only.
- Test vs production: distinct endpoints, distinct users, distinct permissions.

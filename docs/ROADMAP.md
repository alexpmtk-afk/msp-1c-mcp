# Milestones — research first, deployment second

## D0: public source baseline — DONE
- [x] Public repository created with initial diagnostic MCP/CLI code.
- [x] Offline tests and GitHub CI bootstrap.
- [x] Research-first workflow documented; no REMOTE or Hermes dependency.

## D1: locate and inspect real 1C host — NOT STARTED
- [ ] Determine how user logs on (Windows desktop/RDP, 1C client, web UI, etc.).
- [ ] Run the smallest approved read-only host/launcher configuration check.
- [ ] Confirm where the infobase lives (file mode or server mode).
- [ ] Assess safe execution environment adjacent to 1C and the required
      private network route; avoid deploying any remote MCP.

## D2: diagnostic link from ChatGPT workflow — NOT STARTED
- [ ] Select and validate a minimal trusted test executor reachable by 1C.
- [ ] Configure permissions and secrets strictly outside public GitHub.
- [ ] Prove read-only discovery and metadata requests with redacted results.
- [ ] Inventory entity names, fields, relationships and UNF semantics.

## D3: test business operations — NOT STARTED
- [ ] Confirm separate TEST infobase with isolated credentials and data.
- [ ] Verify stock read and cross-check values against 1C UI.
- [ ] Create invoice on TEST base, read it back, verify form and fields.
- [ ] Post invoice on TEST base if applicable; check resulting state.
- [ ] Create/post sales delivery document on TEST base; check its movements.
- [ ] Store accepted scripts, business semantics and tests in this repo.

## D4: MCP production implementation — FUTURE, AFTER D3
- [ ] Convert accepted scripts into typed MCP tools.
- [ ] Integrate with REMOTE `msp-server-stack` and Hermes if authorized.
- [ ] Enforce permissions, approvals, idempotency and audit before
      enabling any production write action.

# Milestones and acceptance

## D0: skeleton — bootstrap
- [x] Project layout, metadata inspector and offline unit tests.
- [x] STDIO MCP diagnostics tools and fixed CLI operations.
- [x] New public GitHub repository created and scaffold pushed.

## D1: environment discovery (no data mutation)
- [ ] Verify physical 1C location / file vs server infobase, OS, publication status.
- [ ] Establish private TLS-reachable endpoint and service account.
- [ ] Publish approved read-only OData subset if appropriate.
- [ ] Add a *whitelisted* `onec-metadata-probe` action to private REMOTE bridge.
- [ ] Verify `$metadata` response, no secrets in logs, no impact on existing services.

## D2: entity and semantic inventory
- [ ] Discover published catalog/document/register names and field types.
- [ ] Map UNF specific stock semantics, invoices, shipments, posting states.
- [ ] Document permissions, constraints, required fields and relationships.

## D3: business tools on TEST base only
- [ ] `onec_stocks` with reconciliation to 1C UI.
- [ ] Create and read back an invoice, then verify UI and business effects.
- [ ] Invoice posting if supported; verify registrations on TEST base.
- [ ] Create/post shipment and verify TEST base stock movements.

## D4: production handoff
- [ ] Implement approved business tools in this MCP repo.
- [ ] Integrate with REMOTE stack inventory and service, no changes to Hermes runtime.
- [ ] Define permission levels, human approvals, audit and rollback strategy.

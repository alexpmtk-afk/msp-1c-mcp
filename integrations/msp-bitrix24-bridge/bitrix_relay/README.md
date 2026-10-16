# Bitrix24 read-only search relay (NOT DEPLOYED)

This prototype is **source only**. It has no production endpoint and has
NOT been connected to the user's Bitrix24 portal. The S3 customer index
remains on physical SRV; do not mirror the 6,433 rows to VPS.

Target flow:
1. Bitrix24 installed local app opens CRM_DETAIL_SEARCH iframe by HTTPS POST
   to `/bitrix/search?DOMAIN=<PINNED_PORTAL>`.
2. Relay checks exact portal and member ID, validates OAuth via HTTPS
   `https://<PINNED_PORTAL>/rest/user.current.json`, then queues one bounded
   query (3-80 Unicode chars, COMPANY/CONTACT, limit 20).
3. Independent SRV service initiates outbound HTTPS GET `/worker/next`.
   Only it sees the short query. It executes the already installed local
   `query-bitrix-search-index.ps1` and POSTs up to 20 resulting GUID/name
   pairs back to `/worker/result` using an independent strong worker secret.
4. Relay returns a transient iframe with `crmShowFoundEntities` results,
   then discards them from process memory. No persistent mirror, no database.
5. **Selection/CRM writes deliberately NOT IMPLEMENTED.**
   onCrmEntityIsNeedToCreate must be wired only after deduplication design,
   source GUID mapping and separate acceptance. Not a complete production
   client creation flow.

Deployment is BLOCKED until: exact Bitrix24 portal host and member ID,
OAuth local app installation, explicit approved public HTTPS hostname and
reverse proxy, approved data transfer of query and up-to-20 results,
rate limiting, secrets provisioning, SDK pinning/self-hosting, a strictly
outbound SRV worker with least-privilege credentials, independent synthetic
E2E test, and rollback procedure. All requests without valid credentials
fail closed. No networking configured automatically.

Never expose SRV's IIS, SQLite file, SMB share, OData service or port 9786.
The existing system agent and Hermes remain unchanged. S4 Option B delta
registration is PAUSED; customer snapshot therefore is not yet live-refreshing.

Local tests: `python -m unittest discover -s bitrix_relay_tests -v`.

References:
- https://apidocs.bitrix24.ru/api-reference/widgets/crm/detail-search.html
- https://apidocs.bitrix24.ru/api-reference/widgets/ui-interaction/bx24-placement-call.html

# REMOTE Bitrix relay — synthetic acceptance gate (NOT DEPLOYED)

## Accepted local prerequisite (SRV, 16 Oct 2026)

- 6,433 customers and 6,433 FTS5 index entries intact, `PRAGMA quick_check=ok`.
- JSON1 installed on the *disabled* LocalService search worker; original worker backed up.
- LocalService audit receipt `bitrix-json1-installed-runtime-status.txt` reported PASS and zero network/1C/Bitrix calls.
- Last diagnostic command reported the temporary audit task as `NOT_FOUND_OR_INACCESSIBLE`; this is **not proof of absence**. A read-only exact task query should distinguish absence from access denied before future provisioning.
- No worker `bitrix-search-worker.ini` or DPAPI token. Never activate automatically.
- This is an **S3 snapshot**, not real-time updates: Option B remains paused.

## Gateway path contract

The installed SRV worker permits only a base URL of the form
`https://vm-817589.tail76ae70.ts.net:<DEDICATED_PORT>/b24-relay`.
It forms GET and POST URLs by appending `/worker/next` and
`/worker/result`.

The Python HTTP handler recognizes **only** `/worker/next`,
`/worker/result`, and `/bitrix/search`. A future HTTPS reverse proxy
**must strip exactly** the public `/b24-relay/` prefix before sending
requests to the loopback-only listener at `127.0.0.1:9814`.
Thus:

| Public HTTPS path (future) | Internal loopback path |
| --- | --- |
| `/b24-relay/worker/next` | `/worker/next` |
| `/b24-relay/worker/result` | `/worker/result` |
| `/b24-relay/bitrix/search` | `/bitrix/search` |

Do **not** assign a port now. Existing port 8443 and the existing 1C
Funnel/relay are reserved and must not be modified. Check actual listener,
firewall, reverse-proxy, Tailscale Serve/Funnel, and TLS configurations on
REMOTE before selecting a distinct endpoint. Bind the Python relay only
to loopback. Never publish the raw listener.

## Only approved first test: local synthetic HTTP E2E

Run from repo checkout (no portal token, no real buyers):

```bash
python3 -m unittest discover -s integrations/msp-bitrix24-bridge/bitrix_relay/bitrix_relay_tests -v
```

`test_synthetic_http_e2e.py` exercises actual loopback HTTP requests
with synthetic IDs, company name, portal/member/app tokens, worker polling,
a bounded reply, iframe rendering, denial of unauthorized calls, and
one-time queue deletion. A successful localhost test is **NOT** evidence
that public HTTPS, Bitrix24 SaaS callbacks, TLS, or SRV↔REMOTE transport
works.

## Blocking gates before a REMOTE deployment

1. Read-only REMOTE listener/Tailscale/HTTPS inventory, document conflicts;
   avoid touching Hermes and the existing 1C relay.
2. Choose and explicitly approve isolated HTTPS reverse proxy and public
   port, implement prefix stripping and TLS validation, deny other paths.
3. Define runtime isolation (non-root account, systemd sandboxing,
   log redaction, rate limiting, resource ceilings, and rollback).
4. Use synthetic credentials only for initial staging and test against
   loopback; do not store secrets in GitHub or chat.
5. Validate **separately** the exact Bitrix24 portal installation,
   actual `member_id`, app-scope `crm,placement,user_basic`,
   `APPLICATION_TOKEN`, OAuth `user.current`, and correct
   `CRM_DETAIL_SEARCH` UI protocol.
6. Obtain explicit approval to transfer even bounded real buyer GUID/name
   results; then gate an authorized single request and audit. No bulk
   export, no CRM writes or 1C modifications.
7. Review response-time budget: the existing relay waits up to 12s for
   a response, and any worker with a long polling cadence may time out.
   Do not claim prompt Bitrix search without measured end-to-end latency.

No production endpoint, service, token, scheduled worker, or HTTPS proxy
has been installed by this documentation.

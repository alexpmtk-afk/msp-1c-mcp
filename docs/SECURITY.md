# Security / operating rules

- No real credentials, connection strings, private hosts, commercial records or extracts in git.
- No unreviewed shells via GitHub issue or arbitrary agent tools.
- Research starts with configuration presence and read-only OData `$metadata`.
- HTTPS with certificate verification is required. No redirects. Prefer private Tailscale routing.
- Create a dedicated 1C read-only account with the least privileges sufficient for diagnostics.
- Do not publish the 1C OData interface on a public host.
- Document writes must use a test copy, explicit approval, strict parameters, idempotency
  keys, complete audit logs, and post-action verification before production activation.
- Never delete/repost production documents as a method of trial-and-error.
- Limit result sizes. Avoid logging full sensitive metadata or data from 1C.
- Authenticate the runner/action, restrict tool discovery and maintain one production writer.

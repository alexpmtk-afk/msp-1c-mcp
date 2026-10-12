# Architecture — ChatGPT research on REMOTE, MCP service later

## Decision (2026-10-12)

**All lasting 1C connector code, configuration and network access will be installed
on the MSP REMOTE VPS (Ubuntu) from the beginning.** In the first phase it will
be a small restricted diagnostic CLI/client, **not** a production MCP service.
Hermes/Codex runtime is not involved in ChatGPT-led research.

Two distinct remote machines must not be conflated:
- **MSP REMOTE VPS (Ubuntu)**: our managed environment for research and eventual
  MCP deployment; future code at `/opt/mcp/projects/msp-1c-mcp/`, connection
  secrets at `/opt/mcp/secrets/onec.env` (file present only after provisioning).
- **1C Windows server**: the machine to which the user logs in via remote
  Windows desktop. Actual infobase location, publication, API and network
  connectivity have **not** been verified.

### Research execution path

ChatGPT -> GitHub source `msp-1c-mcp`
        -> **private, approved** `msp-server-bridge` GitHub Actions
        -> self-hosted REMOTE runner on Ubuntu
        -> restricted/versioned diagnostic client on MSP REMOTE
        -> private TLS network route
        -> 1C Windows (OData or approved dedicated HTTP API)
        -> redacted verification result returned via GitHub.

**This is a target architecture, not yet an operational 1C connection.**
GitHub bridge already exists for approved REMOTE operations, but **no 1C
diagnostic command is yet whitelisted**, no 1C service credentials are stored,
and no network path to 1C has been proven. Do not allow arbitrary shell commands
through GitHub Issues, PRs or Actions. Do not put secrets in GitHub workflow
arguments, logs or commits. Existing REMOTE bridge's runner must use only
explicitly authorized, reviewed 1C diagnostic operations.

Windows/RDP login credentials are **not** automatically 1C API credentials.
Remote desktop access does not itself provide an HTTPS/OData endpoint from
Linux. Host discovery and approval from the Windows/1C administrator are needed
to choose between:
- approved HTTPS/OData or 1C HTTP service exposed over a *private* route;
- a minimal Windows-side bridge only if direct publication is unavailable.
Any Windows-side helper is subordinate to the canonical diagnostic client
on MSP REMOTE. Never expose RDP, database files or 1C API to the public Internet.

## Research milestones, with MCP service disabled

1. Read-only inspect the 1C Windows host and infobase connection configuration.
2. Verify host of database, file-mode vs client-server, and supported publication.
3. Establish authenticated private connection **from MSP REMOTE to 1C** and
   keep credentials outside Git.
4. Deploy the restricted connector CLI on MSP REMOTE and authorize only fixed
   read-only checks through the private GitHub bridge.
5. Read actual OData metadata, dictionaries and stock register structure;
   reconcile to UI with a limited anonymized report.
6. **Only with a separate TEST infobase and explicit approval**, create invoice,
   read it back, compare UI, then test posting and resulting business movements.
7. Add accepted commands, typed schemas, business semantics and regression
   tests to the public `msp-1c-mcp` source without sensitive business records.

## MCP activation — after accepted real tests

Once tested, reuse the **same connector on REMOTE** behind the production
MCP tool handlers, then integrate with the shared `msp-server-stack`
infrastructure and Hermes. Do not activate document write tools on production
without separate explicit operational approval and safeguards.

## Security

- No passwords, private keys, sensitive hosts, cookie/session files, real
  financial documents, production database dumps or full sensitive log output
  in either public repository.
- On REMOTE store secrets with restrictive permissions, only accessible by
  the designated connector service user; never log or echo the values.
- Authenticated private routing and HTTPS certificate verification required.
- Independent 1C read-only user for diagnosis; separate test infobase credentials
  for write trials. No arbitrary execution of 1C code.
- The current GitHub runner/bridge is transport, not proof of working access
  to the external 1C host.

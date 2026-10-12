# Architecture — research-first workflow

## Decision (2026-10-12)

**Phase 1 is direct research from ChatGPT with GitHub as the canonical code store.**
Do not deploy the 1C MCP to the REMOTE VPS, route experiments through Hermes, or
depend on the REMOTE self-hosted runner at this stage.

ChatGPT -> GitHub `msp-1c-mcp` (versioned code and test plans)
              -> an **authorized diagnostic executor** that can reach the 1C host
              -> 1C (read metadata, then test approved business operations)
              -> redacted verification results -> ChatGPT -> GitHub fixes.

GitHub **cannot by itself** log into an arbitrary Windows/RDP machine or connect to
an unexposed 1C database. Execution requires a real network path, approved
credentials, and an executor on/near the 1C host. Possible models to evaluate
after host discovery:
- a small temporary read-only program executed on the 1C host or an authorized
  Windows workstation (initially invoked manually, later automated);
- an authenticated HTTPS OData endpoint over a private network, used by a
  carefully restricted, approved test executor;
- a private GitHub Actions runner on a **dedicated trusted machine** with
  connectivity and controlled repository/workflow permissions (never attach
  a production 1C host as a runner executing arbitrary public PRs).

Do not assume the existing REMOTE GitHub bridge is the 1C network transport;
no such connection has been confirmed. No public GitHub Actions runner is presumed
to have 1C network connectivity.

## Phase 1 research steps

1. Inventory the actual host and 1C launch/infobase configuration using bounded,
   read-only checks; never copy secret-containing configuration or database files
   to public GitHub.
2. Identify whether 1C is file-mode or client-server and whether OData/HTTP
   services are published and reachable through an approved secure route.
3. Explore actual 1C metadata, catalogs, documents and stock registers.
4. Reconcile script responses with the 1C application's observable state.
5. Trial invoice creation and posting **only on a controlled TEST infobase**
   following explicit approval, then independently verify document state and
   accounting/stock movements.
6. Commit tested commands, schemas, semantic definitions, safe synthetic
   fixtures and documented expected results to `msp-1c-mcp`.

## Phase 2 deployment (only when phase 1 tests pass)

ChatGPT/Hermes -> deployed `msp-1c-mcp` on REMOTE -> specialized MCP
tools -> 1C through an approved secure route.

The public `msp-server-stack` is canonical for shared infrastructure, while
this repository is canonical for the 1C integration source and semantics.

## Security requirements

- No passwords, cookies, internal hostnames, full production metadata dumps,
  user records, document amounts or credentials committed to public Git.
- Credentials held in a protected store on the executor, never pasted into chat.
- No arbitrary command execution, unbounded reads, disabled TLS verification,
  unreviewed privilege escalation or direct writes to production for exploration.
- Initial test accounts must have read-only permission. Write tests require a
  separate TEST infobase, distinct credentials, explicit approval and audit.
- Verify whether OData calls execute the same business validations/form
  processing as 1C's UI, especially when posting documents.

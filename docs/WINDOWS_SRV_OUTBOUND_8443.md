# SRV Windows outbound agent — probe-only stage

**Status:** Source prepared; native Windows Server 2008 R2 / PowerShell 2 acceptance pending.

The Windows SRV agent polls a pinned HTTPS 8443 URL and returns SRV_ALIVE only for an allowlisted probe task. It does not access 1C, COM, OData, IIS, or production data.

- scripts/windows/onec-enroll-token.ps1: hidden token input, user-scoped DPAPI encryption, profile-local encrypted storage.
- scripts/windows/onec-probe-poll.ps1: one-shot HTTPS poll using approved portable curl with TLS certificate verification, bounded replies and persistent retry-on-ACK-loss.
- Public source files include **zero credentials**; never paste the agent token in ChatGPT, GitHub issues, screenshots, or logs.
- The agent token is generated on VPS in /home/hermes/.config/onec-relay/queue.env, under ONEC_AGENT_TOKEN. A root SSH user may display it locally, then paste privately into the hidden SRV enrollment prompt. ONEC_OPERATOR_TOKEN never leaves VPS.

## Acceptance stages

1. SRV unauthenticated public TLS smoke: HTTP 401, CERT_VERIFY=0, CURL_EXIT=0 — PASS on 2026-10-14.
2. Download approved PowerShell files via verified TLS; enroll locally under the same Windows user as poller. Run the poller manually once, requiring RESULT=PASS;STAGE=AUTHENTICATED_EMPTY.
3. Submit exactly one probe from the GitHub whitelist on VPS and run the poller manually. Require returned DONE with matching task ID.
4. Only then configure periodic unattended polling, ensuring it works when RDP is closed.
5. In a **separate reviewed step**, add fixed GET-only OData diagnostics for the test infobase NewBase; store 1C credentials in Windows DPAPI, not GitHub. Verify application-level write denial and limit OData exposure before accessing business records.
6. Register / verify approved remote MCP tools. Never enable production writes without a separate authorization and audit.

Do not confuse a successful TLS connectivity test with an authenticated agent round trip or a live remote 1C connection.

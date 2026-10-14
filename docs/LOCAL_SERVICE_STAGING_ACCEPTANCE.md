# LocalService stage: server preparation, not activation

The stage is intentionally separate from the future cutover. **Do not
disable the personal task until an independent system-agent health test
and rollback are available.**

## Preconditions

- Windows Server 2008 R2 / PowerShell 2 under the same local Windows
  identity which originally enrolled the existing agent DPAPI token.
- Read-only `onec-localservice-preflight.ps1` outputs
  `RESULT=PASS` and `CURRENT_PROCESS_ADMIN=YES`.
- Existing user task `MspOnecHttpsAgentProbe` is enabled and continues
  to poll the fixed `probe` queue at HTTPS 8443.
- Local existing portable curl.exe and curl-ca-bundle.crt are available.
- A reviewer verifies the exact GitHub merge commit used to download
  `onec-system-stage.ps1` and `onec-system-probe-poll.ps1`.

## Stage procedure

1. Download pinned review-merged scripts into
   `%LOCALAPPDATA%\MspOnecAgent\bin` using existing TLS-verified
   portable curl with `--proto =https`, no redirects.
2. Run `onec-system-stage.ps1` once with approved host/account,
   portable curl and CA bundle paths.
3. Require `RESULT=PASS`,
   `OLD_DPAPI_TO_MACHINE_DPAPI=PASS`,
   `LOCAL_SERVICE_FILE_ACL=STAGED`,
   `PERSONAL_AGENT_TASK=UNCHANGED`,
   `NEW_SYSTEM_TASK=NOT_CREATED`,
   `SYSTEM_AGENT_EXECUTION=NOT_TESTED`.
4. Independently confirm the previous GitHub-only `probe` still
   works on the original scheduler after staging.
5. Later, release an isolated task activation/rollback PR. Activation
   must check LocalService identity on target, then disable the old task
   only in a controlled cutover with automatic restoration on failure.

## Intended layout

`%ProgramData%\MspOnecAgent\bin` — PowerShell probe, portable
curl.exe, CA certificate bundle and required adjacent DLLs;
`config\endpoint.txt` — pinned HTTPS 8443 URL;
`secrets\agent-token.machine.dpapi` — encrypted token bytes for machine
DPAPI (no plaintext storage);
`state\` — LocalService-writable bounded ephemeral poll files and
sanitized `last-status.txt` health output.

Only LocalService and Administrators/SYSTEM have access to the installed
tree. LocalService may **read/execute** bin/config/secrets but may
**modify** state only. Machine-scoped DPAPI is protected by OS-machine
keys but requires restricted filesystem ACLs as above.

**This interim stage copies the current agent credential** into a
machine-bound form without displaying it. A separate token-rotation
phase should be considered after system migration to minimize
old-credential exposure. Public logs must never contain tokens,
passwords, or protected data.

## Failure / rollback

If the stage detects an error after creating its destination root it
attempts to delete **only its newly created tree**, preserving all
legacy tasks, user DPAPI files, VPS/Hermes and 1C services. If a stage
fails after partial creation and root still exists, do not blindly
rerun or delete; inspect ACLs and generated files first.

This stage is NOT proof that LocalService can execute the scheduled
task or authenticate to VPS. That requires an actual controlled run.

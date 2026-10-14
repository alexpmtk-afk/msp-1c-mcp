# LocalService Task Scheduler registration — manual-only acceptance

This stage operates on **staged and verified** files under
`%ProgramData%\MspOnecAgent\`. It is the next, separately reversible gate
after source staging, not yet the permanent migration.

## Register (never switch automatically here)

Run `scripts/windows/onec-system-task-register.ps1` on Windows Server
2008 R2 / Windows PowerShell 2 under the operator who performed staging,
with parameters `-ExpectedComputerName` and `-ExpectedAccount`.

Preconditions: Windows administrator, original `MspOnecHttpsAgentProbe`
enabled, approved system files and DPAPI token present, system task absent.

Registers exactly ONE additional Task Scheduler 2.0 task:

- Name `MspOnecHttpsAgentSystem`.
- Principal built-in LocalService SID `S-1-5-19`; translated to the
  locally understood account name; `TASK_LOGON_SERVICE_ACCOUNT=5`;
  no password or user-linked DPAPI; run level least privilege (0).
- Fixed PowerShell script path inside ProgramData with only the reviewed
  curl binary and CA bundle.
- **Daily trigger exists but is disabled.** The task itself allows
  manual start: the operator can exercise `IRegisteredTask.Run`
  without creating a second unattended polling loop.
- Task execution bounded to two minutes; overlapped runs skipped.
- No OData/1C operations, TCP listener, Windows service or login changes.
- Source task remains enabled and unchanged.

Require output `RESULT=PASS`,
`RUN_AS_LOCAL_SERVICE=YES`,
`AUTOMATIC_TRIGGER_ENABLED=NO`,
`OLD_AGENT_ENABLED=YES`,
`SYSTEM_AGENT_EXECUTION=NOT_YET_TESTED`.

If registration fails, do not proceed. Check `FAILURE_PHASE` and whether
the script performed an isolated rollback; never remove existing task.

## Smoke after successful registration (separate user-confirmed step)

Under administrator session, execute
`scripts/windows/onec-system-task-smoke.ps1` using the fixed target
computer name. The smoke launches only the *inert* system task on
demand, waits for newly written `%ProgramData%\MspOnecAgent\state\last-status.txt`,
and requires healthy `POLL_OK` or `PROBE_ACK`.
It does not enable the task's periodic trigger.
The old user task must remain enabled and is neither restarted nor
modified.

The health file is a bounded code+UTC timestamp, no tokens or raw
responses. A successful smoke indicates a LocalService execution path,
machine DPAPI decryption and HTTPS agent poll were successful, but
does **not** by itself validate permanent post-cutover operation.

## Later controlled cutover (not part of this PR)

Implement a dedicated, independently reviewed PS2 cutover+rollback:
disable original schedule, enable system schedule, validate system-only
job ID through Github↔VPS↔SRV↔VPS↔Github, and restore old schedule on
bounded failure. Distinguish agent identities beyond shared legacy
credential when possible. Only after acceptance revoke personal task
and rotate old credentials.

Never reboot the Windows server solely for this test.

# One-time cutover: user polling -> LocalService auto polling

State before acceptance: user-run `MspOnecHttpsAgentProbe` enabled;
`MspOnecHttpsAgentSystem` installed and on-demand smoke PASSED,
but its automatic trigger is disabled. The system agent already has
machine DPAPI token and TLS-verified curl in ProgramData.

## PS2 atomic cutover gate

From approved administrative Windows session with the existing working
user account, run the reviewed pinned
`scripts/windows/onec-system-cutover.ps1` with exact expected machine
name and expected operator account (not passwords).

The script checks both exact Task Scheduler identities, ensures the
system task is LocalService (SID S-1-5-19), non-elevated, fixed approved
agent path, program files and DPAPI token exist, legacy enabled and
system trigger currently disabled. It then:

1. Stops *scheduling* the old task. Existing ongoing process may finish
   but it will not start new runs.
2. Registers the system task's minute-based daily trigger with a
   start time 30 seconds in the future, keeping the user task intact.
3. Waits **at most 150 seconds** for a freshly timestamped system-only
   health update AND a new actual Windows Task Scheduler `LastRunTime`.
   No manual system task run is used here.
4. If healthy, requires legacy schedule still disabled and system
   schedule enabled. Reports local timer acceptance PASS.
5. On failure, attempts to re-enable user task FIRST, then disarm system
   trigger. Diagnostic output contains only fixed error codes.

**Limit:** A PowerShell process terminated abruptly (crash, forced close,
power loss) cannot execute its in-process rollback. For that reason,
do not close the elevated SRV console during the cutover. The
`onec-system-rollback.ps1` file allows manual rollback. An
independent watchdog/task would be needed for a hard guarantee against
abrupt interruption.

## Independent GitHub end-to-end acceptance

Following local `RESULT=PASS`, **disconnect RDP** without logging
off or powering down SRV and request one new owner-gated
`[REMOTE] onec-https-probe` issue in private `msp-server-bridge`.
No manual polling. Require an issue result with one matching
TASK_ID and `RESULT=PASS`. Because old schedule was turned off and
system timer confirmed fresh, this confirms actual system-only
transport. Do not count pre-cutover GitHub probes.

Do not confuse local `POLL_OK` with a full GitHub end-to-end
acceptance; local cutover's `GITHUB_ROUNDTRIP=NOT_YET_TESTED`
is intentional.

## Manual rollback

Run `onec-system-rollback.ps1` using the same expected host/account.
It restores the original task FIRST, then disarms the system trigger
without deleting either task. Confirm
`PERSONAL_AGENT_RESTORE=PASS`,
`SYSTEM_TIMER_DISARM=PASS` and `RESULT=PASS`.

Do not delete old user task or DPAPI enrollment, change gateway secrets,
restart Windows or access 1C until independent cutover acceptance and a
separate reviewed credential rotation plan.

No 1C reads, COMConnector, OData, 1C writes or IIS changes in either
cutover or rollback.

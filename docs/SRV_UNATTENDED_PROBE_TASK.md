# SRV unattended 1C PROBE poller — PowerShell 2 / Windows 2008 R2

## Limits and security

This is ONLY a fixed HTTPS poll of the pre-existing `probe` transport.
No COM, OData, 1C reads or writes, dynamic commands or arbitrary remote URLs.
Windows scheduled task name: `MspOnecHttpsAgentProbe`.

Use Windows Task Scheduler 2.0 COM, because the built-in PowerShell 2
installation does not have modern `ScheduledTasks` cmdlets.
The task runs **every minute**, not at boot as SYSTEM, under the **same
Windows user that enrolled the token** via DPAPI. The Windows password is
entered **locally using a hidden prompt**, transferred directly to
Schedule.Service COM at task registration, never added to command line,
logs, GitHub or ChatGPT. Windows stores the scheduled-logon credential.
Do not select S4U / "Do not store password", which cannot access DPAPI
encrypted files. Do not use "run only when logged on", which fails after
logging out. Do not enable "highest privileges".

## Local-only acceptance

1. On SRV, first run `scripts/windows/onec-task-preflight.ps1` with
   `-ExpectedComputerName` and `-ExpectedAccount` matched to the
   actual Windows host/identity and the existing **portable curl** binary
   and CA-bundle file. Must report `NO_LOCAL_CHANGES=YES; RESULT=PASS`.
2. Run `onec-task-install.ps1` with the same four parameters. Enter
   the Windows account password **privately on SRV**. Installer does not
   print the password or the agent token. Installs exactly one
   non-elevated task, TASK_LOGON_PASSWORD=1, using an every-minute daily
   trigger and skip-new overlapping task instances. If registration
   fails, it does not modify any other tasks and only attempts rollback
   of the newly created task.
3. Wait at least 2 minutes, then run `onec-task-status.ps1`.
   Require `PASSWORD_LOGON=YES`, `NON_ELEVATED=YES`,
   `EVERY_MINUTE=YES`, `RECENT_EXECUTION=YES`,
   `LAST_RESULT_ZERO=YES`, `RESULT=PASS`.
4. **Independent unattended acceptance**: disconnect RDP / close the
   interactive shell (but leave SRV powered on) and ask ChatGPT to
   queue exactly one owner-gated `[REMOTE] onec-https-probe` through
   private `msp-server-bridge`. GitHub must report matching
   task ID and `RESULT=PASS` with **no manual polling**.
5. Then, separately test task behavior after an approved SRV restart.
   Do not reboot the Windows host solely for this change without
   explicit server-owner approval.

## Rollback

Run `onec-task-remove.ps1` on SRV as the enrolling user. It deletes
only `MspOnecHttpsAgentProbe`. It leaves all DPAPI protected secrets,
approved curl installation, IIS/1C, Windows services and other schedules
untouched. To remove token enrollment separately, use a deliberate
new authorization and secret-handling plan.

Never paste account passwords, bearer tokens, PowerShell environment
contents, or local encrypted DPAPI files into GitHub or ChatGPT.

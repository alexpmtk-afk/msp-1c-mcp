# SRV file ACL recovery (15 Oct 2026)

Observed after first partial install: root, bin/config/state directory ACLs hold
SYSTEM F, Administrators F, LocalService RX (state LocalService M), but
bin\bridge.ps1 and config\bridge.ini have **empty discretionary ACLs**.
The initial installer had called icacls /inheritance:r with /T over all files.

Consequences: a LocalService scheduled task can show LastTaskResult 0 even
when the expected SAFE_IDLE heartbeat file is never created. Windows Scheduler
results alone do not prove code execution. Auto-triggers MUST remain disabled.

## Remediation

Use bin/repair-file-acl.ps1 from a SHA256-pinned download run **on physical SRV**
in an elevated PowerShell 2 session. It:
- checks exactly SRV, known root, task identity, disabled triggers and action
- validates paths and rejects reparse points
- applies explicitly allowlisted SID grants only to two named files, no /T
- confirms both file hashes equal reviewed original bytes
- confirms ACLs contain SYSTEM/Administrators/LocalService ALLOW entries
- does NOT run the task, enable triggers, access 1C, or touch any other MSP component

On any failure, do NOT simply retry. Read FAILURE_PHASE and investigate. If
Windows denies setting file ACLs because the admin is not owner, do NOT take
ownership of the directory recursively. Review exact two file owners/permissions first.

After repair PASS, separately rerun known, pinned smoke-system.ps1 for actual
LOCAL_SERVICE SAFE_IDLE heartbeat. Only after a successful smoke should system
auto-triggers be considered.

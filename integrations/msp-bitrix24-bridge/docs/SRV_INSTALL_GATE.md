# SRV installation gate — no implicit deployment

This gate applies to physical Windows Server 2008 R2, not VPS and not a user's Windows workstation.

Before installation:
1. Native PowerShell 2.0 parser check for all bin/*.ps1 using the pinned source revision.
2. Confirm full SRV backup/recovery and change window with administrator.
3. Run preflight.ps1; expect MACHINE_MATCH=True, POWERSHELL_2=True, BRIDGE_TASK=ABSENT.
4. Inspect Task Scheduler COM API support, output permissions and system account before mutation.
5. Inspect/install only after owner approval; staging source must be trusted and hash checked against reviewed release.
6. Run install-system.ps1 once as administrator. It only creates MspBitrix24Bridge and ProgramData contents. Initial state SAFE_IDLE.
7. Run task and status. Log off RDP and confirm status changes after 5 minutes. Test reboot independently at the next maintenance window; do not reboot production SRV solely for this test.
8. If any problem, run rollback-system.ps1 -ConfirmDisable, inspect task, do not touch working MSP queue/agent.

No customer synchronization can work at this stage. No secret or Bitrix webhook may be supplied until a separate reviewed credential-enrollment and data-mapping change is ready. Do not elevate LocalService or make the SRV a public web server.

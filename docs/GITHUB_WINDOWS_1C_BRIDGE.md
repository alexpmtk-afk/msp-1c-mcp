# GitHub ↔ Windows ↔ 1C sandbox diagnostics

Status: **CODE PREPARED, NOT CONNECTED / NOT ACCEPTED**, 2026-10-12.

## Why a Windows executor is necessary

The tested 1C platform's `V85.COMConnector` is a Windows COM component.
It ran successfully inside the legacy 1C server and made an authenticated
COM connection **only to an independently identified test sandbox**.
The GitHub runner currently on MSP REMOTE is **Linux** and cannot use that
Windows COM object directly. A GitHub repository or workflow alone does
not establish network or authenticated access to the 1C server.

## Temporary Windows 10 runner architecture

```text
ChatGPT
  -> PRIVATE msp-server-bridge (owner-only fixed GitHub issue commands)
  -> GitHub Actions / separate Windows 10 self-hosted runner
  -> Windows PowerShell Remoting (WinRM) across pre-existing LAN
  -> 1C Windows server (PowerShell 2.0, 1C COM 8.5)
  -> separate TEST file-mode infobase only
  -> sanitized diagnostic output -> private GitHub issue
```

Dedicated runner label: `onec-win`. **Do not register this runner as a
Linux REMOTE runner or put it on legacy Windows Server 2008 R2.** Current
Windows GitHub runner setup is pending.

The only issue commands enabled by the new private workflow are:

- `[1C] sandbox-check` — test authenticated COM connection to sandbox.
- `[1C] sandbox-metadata` — request bounded counts of defined object types.

The workflow accepts only issues opened by the repository owner. It never
evaluates issue bodies or arbitrary issue-supplied code. Windows diagnostic
source and workflow live in PRIVATE `msp-server-bridge` under
`scripts/onec/` and `.github/workflows/onec-sandbox-windows-bridge.yml`.
The workflows run **nothing** until a dedicated Windows runner is connected
under the required label.

## Bootstrap acceptance

1. Confirm remote Windows server **WinRM** is usable from the Windows 10
   workstation without changing networking or firewall settings. A
   read-only `Test-WSMan` and authenticated remoting test are distinct.
2. Install the current supported GitHub Actions Windows runner on
   the Windows 10 workstation, associated **only with the private
   `msp-server-bridge` repo** and isolated by runner label `onec-win`.
   Run it as the Windows identity for which credential setup is performed.
   This is a one-time local installation; if the PC is off, jobs queue.
3. On the workstation, run the reviewed local setup script **once**. It
   prompts for LAN server address, exact TEST sandbox path and two
   distinct credentials (WinRM and test-infobase). Secrets are DPAPI
   protected **locally for the runner identity**, never committed to Git
   or sent to ChatGPT.
4. Create the owner-only GitHub issue `[1C] sandbox-check`; verify result
   appears as a private issue comment and production is untouched.
5. Then try `[1C] sandbox-metadata`; diagnose structured errors from the
   issue result without repeatedly sending long commands over RDP.

IMPORTANT: If this Windows account lacks permission to use WinRM on the
legacy server, stop at step 1. Do not disable authentication, allow all
TrustedHosts, open WinRM/RDP to the Internet, modify routing/DNS, or
install a modern GitHub runner on unsupported Windows Server 2008 R2.
If a narrowly scoped client TrustedHosts entry is ultimately required,
it must be a separate, reviewed one-time step.

## Security and limits

- No automatic production infobase discovery or switching. Live DB remains
  prohibited for all diagnostic COM operations.
- No arbitrary GitHub shell, 1C Query(), Evaluate(), or object write
  operations are exposed. The first step reports only connection status and
  metadata counts.
- The original workstation Tailscale subnet-router pilot was aborted after
  disruption to Internet connectivity; **keep Windows IP forwarding off**.
- This development architecture depends on the workstation being powered on
  and running the agent. Production 24/7 requires a separate always-on,
  supported integration endpoint.
- A `PASS` on COM sandbox does not prove end-to-end GitHub-to-Windows
  transport. End-to-end acceptance remains pending.

# OData credentials on legacy SRV (15 Oct 2026)

For every manual read-only OData diagnostic script used in this integration:
- Hard-code only the **account name** `MCP_OData_ReadOnly` (public configuration, not a secret).
- Do not require retyping username: ask only `Read-Host -AsSecureString` for the password.
- Construct the PSCredential **inside native PowerShell 2.0 process** using `New-Object System.Management.Automation.PSCredential`.
- Do not store, echo, save, log, or pass the password on a process command line.
- Forbid a different supplied `-Credential` account.
- Never use `Get-Credential -UserName`: introduced only with PowerShell 3.0.

Affected five scripts:
`inspect-customers-metadata.ps1`,
`inspect-customers-schema.ps1`,
`inspect-customers-counts.ps1`,
`inspect-customers-required-counts.ps1`,
`diagnose-customer-string-filters.ps1`.

The active `MspBitrix24Bridge` system task remains SAFE_IDLE with no 1C or
Bitrix24 API access. These manual diagnostic scripts must not be registered
as scheduled tasks.

Reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-credential

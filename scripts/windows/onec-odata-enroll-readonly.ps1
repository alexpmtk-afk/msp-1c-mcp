#requires -version 2
# Local, one-time OData read-only credential enrollment on SRV.
# Never accepts credentials via CLI, GitHub, HTTP, issue text or environment variables.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$ptr=[IntPtr]::Zero
[byte[]]$clearBytes=$null
[byte[]]$sealed=$null
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$dest=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  $ident=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $ident
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ADMIN_REQUIRED' }
  if ([Environment]::OSVersion.Version.Major -ne 6 -or [Environment]::OSVersion.Version.Minor -ne 1) { throw 'WRONG_OS' }
  if (-not (Test-Path -LiteralPath (Join-Path $root 'bin\onec-system-probe-poll.ps1') -PathType Leaf)) { throw 'SYSTEM_AGENT_MISSING' }
  if (-not (Test-Path -LiteralPath (Join-Path $root 'secrets') -PathType Container)) { throw 'SECRET_DIR_MISSING' }
  if (Test-Path -LiteralPath $dest) { throw 'ALREADY_ENROLLED' }
  $phase='LOCAL_PASSWORD_PROMPT'
  $cred=Get-Credential -Credential 'MCP_OData_ReadOnly'
  if ($null -eq $cred -or $cred.UserName -cne 'MCP_OData_ReadOnly') { throw 'WRONG_1C_ACCOUNT' }
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password)
  $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  if (-not $plain -or $plain.Length -gt 256) { throw 'INVALID_PASSWORD' }
  $phase='MACHINE_DPAPI_PROTECT'
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $clearBytes=[Text.Encoding]::UTF8.GetBytes($plain)
  $sealed=[Security.Cryptography.ProtectedData]::Protect($clearBytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  [IO.File]::WriteAllBytes($dest,$sealed)
  $phase='RESTRICT_FILE_ACL'
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $dest '/inheritance:r' '/grant:r' '*S-1-5-18:F' '*S-1-5-32-544:F' '*S-1-5-19:R' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'FILE_ACL_FAILED' }
  Write-Output 'ONEC_ODATA_CREDENTIAL_ENROLL'
  Write-Output 'ACCOUNT=MCP_OData_ReadOnly'
  Write-Output 'MACHINE_DPAPI=PASS'
  Write-Output 'LOCAL_SERVICE_READ_ACL=PASS'
  Write-Output 'PASSWORD_EXPORTED=NO'
  Write-Output 'AGENT_TASK_UNCHANGED=YES'
  Write-Output 'RESULT=PASS'
} catch {
  if ($phase -eq 'RESTRICT_FILE_ACL') { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
  $known=@('WRONG_MACHINE','ADMIN_REQUIRED','WRONG_OS','SYSTEM_AGENT_MISSING','SECRET_DIR_MISSING','ALREADY_ENROLLED','WRONG_1C_ACCOUNT','INVALID_PASSWORD','FILE_ACL_FAILED')
  $reason=$_.Exception.Message
  if ($known -notcontains $reason) { $reason='ENROLLMENT_FAILED' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  exit 1
} finally {
  $plain=$null
  if ($null -ne $clearBytes) { [Array]::Clear($clearBytes,0,$clearBytes.Length) }
  if ($null -ne $sealed) { [Array]::Clear($sealed,0,$sealed.Length) }
  if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

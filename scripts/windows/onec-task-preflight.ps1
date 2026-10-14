#requires -version 2
# READ-ONLY diagnostic for legacy SRV Task Scheduler 2.0 and user DPAPI context.
param(
  [Parameter(Mandatory=$true)][string]$ExpectedComputerName,
  [Parameter(Mandatory=$true)][string]$ExpectedAccount,
  [Parameter(Mandatory=$true)][string]$CurlExe,
  [Parameter(Mandatory=$true)][string]$CaBundle,
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'MspOnecAgent')
)
$ErrorActionPreference='Stop'
$taskName='MspOnecHttpsAgentProbe'
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  $identity=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ($identity -ne $ExpectedAccount) { throw 'WRONG_IDENTITY' }
  $poll=Join-Path $StateDir 'bin\onec-probe-poll.ps1'
  $enrolled=Join-Path $StateDir 'agent-token.dpapi'
  $address=Join-Path $StateDir 'endpoint.txt'
  foreach($p in @($poll,$CurlExe,$CaBundle,$enrolled,$address)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'REQUIRED_LOCAL_FILE_MISSING' }
  }
  $txt=[IO.File]::ReadAllText($address,[Text.Encoding]::ASCII).Trim()
  if ($txt -notmatch '^https://[a-z0-9-]+\.tail[a-z0-9-]+\.ts\.net:8443$') {
    throw 'INVALID_HTTPS_ENDPOINT'
  }
  $secure=ConvertTo-SecureString -String ([IO.File]::ReadAllText($enrolled,[Text.Encoding]::UTF8).Trim())
  if ($secure.Length -lt 32 -or $secure.Length -gt 128) { throw 'DPAPI_TOKEN_LENGTH' }
  $secure.Dispose()
  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $root=$service.GetFolder('\')
  foreach($task in $root.GetTasks(0)) {
    if ($task.Name -eq $taskName) { throw 'TASK_ALREADY_EXISTS' }
  }
  Write-Output 'ONEC_SRV_TASK_PREFLIGHT'
  Write-Output 'MACHINE_AND_USER=PASS'
  Write-Output 'DPAPI_UNSEAL=PASS'
  Write-Output 'FIXED_HTTPS_ENDPOINT=PASS'
  Write-Output 'LEGACY_TASK_SCHEDULER_COM=PASS'
  Write-Output 'TASK_NAME_AVAILABLE=PASS'
  Write-Output 'NO_LOCAL_CHANGES=YES'
  Write-Output 'RESULT=PASS'
} catch {
  $reason=$_.Exception.Message
  $allow=@('WRONG_MACHINE','WRONG_IDENTITY','REQUIRED_LOCAL_FILE_MISSING',
    'INVALID_HTTPS_ENDPOINT','DPAPI_TOKEN_LENGTH','TASK_ALREADY_EXISTS')
  if ($allow -notcontains $reason) { $reason='WINDOWS_PREREQUISITE_ERROR' }
  Write-Output ('RESULT=FAIL;GATE='+$reason)
  exit 1
}

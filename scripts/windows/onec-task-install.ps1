#requires -version 2
# Registers a single non-elevated, password-logon task under the approved user.
# Windows Server 2008 R2 Task Scheduler 2.0 COM. No 1C/COMConnector calls.
# Password entered in hidden console prompt and passed only to Schedule.Service COM.
param(
  [Parameter(Mandatory=$true)][string]$ExpectedComputerName,
  [Parameter(Mandatory=$true)][string]$ExpectedAccount,
  [Parameter(Mandatory=$true)][string]$CurlExe,
  [Parameter(Mandatory=$true)][string]$CaBundle,
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'MspOnecAgent')
)
$ErrorActionPreference='Stop'
$taskName='MspOnecHttpsAgentProbe'
$registered=$false
$ptr=[IntPtr]::Zero
$password=$null
$secret=$null
$root=$null
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  $username=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ($username -ne $ExpectedAccount) { throw 'WRONG_IDENTITY' }
  $script=Join-Path $StateDir 'bin\onec-probe-poll.ps1'
  $encrypted=Join-Path $StateDir 'agent-token.dpapi'
  $endpoint=Join-Path $StateDir 'endpoint.txt'
  foreach($path in @($script,$CurlExe,$CaBundle,$encrypted,$endpoint)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'MISSING_FILE' }
    if ($path.Contains('"') -or $path.Contains([char]10) -or $path.Contains([char]13)) {
      throw 'INVALID_FILE_PATH'
    }
  }
  $address=[IO.File]::ReadAllText($endpoint,[Text.Encoding]::ASCII).Trim()
  if ($address -notmatch '^https://[a-z0-9-]+\.tail[a-z0-9-]+\.ts\.net:8443$') {
    throw 'INVALID_ENDPOINT'
  }
  $dpapi=ConvertTo-SecureString -String ([IO.File]::ReadAllText($encrypted,[Text.Encoding]::UTF8).Trim())
  if ($dpapi.Length -lt 32 -or $dpapi.Length -gt 128) { throw 'TOKEN_INVALID' }
  $dpapi.Dispose()

  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $root=$service.GetFolder('\')
  foreach($existing in $root.GetTasks(0)) {
    if ($existing.Name -eq $taskName) { throw 'TASK_ALREADY_EXISTS' }
  }

  $definition=$service.NewTask(0)
  $definition.RegistrationInfo.Description='MSP 1C sandbox outbound probe-only poller; no 1C writes'
  $definition.Principal.UserId=$username
  $definition.Principal.LogonType=1
  $definition.Principal.RunLevel=0

  $settings=$definition.Settings
  $settings.Enabled=$true
  $settings.MultipleInstances=2
  $settings.StartWhenAvailable=$true
  $settings.AllowDemandStart=$true
  $settings.DisallowStartIfOnBatteries=$false
  $settings.StopIfGoingOnBatteries=$false
  $settings.ExecutionTimeLimit='PT3M'

  $trigger=$definition.Triggers.Create(2)
  $trigger.Enabled=$true
  $trigger.StartBoundary=(Get-Date).AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ss')
  $trigger.DaysInterval=1
  $trigger.Repetition.Interval='PT1M'
  $trigger.Repetition.Duration='P1D'
  $trigger.Repetition.StopAtDurationEnd=$false

  $action=$definition.Actions.Create(0)
  $action.Path=(Join-Path $PSHOME 'powershell.exe')
  $action.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
      $script + '" -CurlExe "' + $CurlExe + '" -CaBundle "' + $CaBundle + '"')

  $secret=Read-Host 'Enter Windows password for current SRV account (hidden)' -AsSecureString
  if ($null -eq $secret -or $secret.Length -eq 0) { throw 'PASSWORD_REQUIRED' }
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
  $password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  $task=$root.RegisterTaskDefinition($taskName,$definition,2,$username,$password,1,$null)
  $registered=$true
  if ($null -eq $task) { throw 'TASK_REGISTRATION_FAILED' }
  $password=$null
  if ($task.Definition.Principal.LogonType -ne 1) { throw 'TASK_WRONG_LOGON_TYPE' }
  if ($task.Definition.Principal.RunLevel -ne 0) { throw 'TASK_WRONG_PRIVILEGE_LEVEL' }
  Write-Output 'ONEC_SRV_SCHEDULE_INSTALL'
  Write-Output 'TASK_REGISTERED=YES'
  Write-Output 'LOGON_MODE=PASSWORD'
  Write-Output 'HIGHEST_PRIVILEGES=NO'
  Write-Output 'REPEAT_EVERY_MINUTE=YES'
  Write-Output 'READ_ONLY_PROBE=YES'
  Write-Output 'TASK_EXECUTION=NOT_YET_VERIFIED'
  Write-Output 'RESULT=PASS'
} catch {
  if ($registered -and $null -ne $root) {
    try { $root.DeleteTask($taskName,0) } catch {}
  }
  $reason=$_.Exception.Message
  $known=@('WRONG_MACHINE','WRONG_IDENTITY','MISSING_FILE','INVALID_FILE_PATH',
    'INVALID_ENDPOINT','TOKEN_INVALID','TASK_ALREADY_EXISTS','PASSWORD_REQUIRED',
    'TASK_REGISTRATION_FAILED','TASK_WRONG_LOGON_TYPE','TASK_WRONG_PRIVILEGE_LEVEL')
  if ($known -notcontains $reason) { $reason='TASK_SCHEDULER_COM_FAILURE' }
  Write-Output ('RESULT=FAIL;GATE='+$reason)
  exit 1
} finally {
  $password=$null
  if ($ptr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
  if ($null -ne $secret) { $secret.Dispose() }
}

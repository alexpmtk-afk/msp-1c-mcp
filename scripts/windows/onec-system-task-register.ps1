#requires -version 2
# Register ONLY an inert, manually runnable LocalService probe task.
# Timer trigger stays DISABLED. Old user task remains unchanged.
param(
  [Parameter(Mandatory=$true)][string]$ExpectedComputerName,
  [Parameter(Mandatory=$true)][string]$ExpectedAccount
)
$ErrorActionPreference='Stop'
$name='MspOnecHttpsAgentSystem'
$registered=$false
$phase='PRECONDITIONS'
$root=$null
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  $windows=[Security.Principal.WindowsIdentity]::GetCurrent()
  if ($windows.Name -ne $ExpectedAccount) { throw 'WRONG_OPERATOR' }
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $windows
  if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ADMIN_REQUIRED' }
  if ([Environment]::OSVersion.Version.Major -ne 6 -or
      [Environment]::OSVersion.Version.Minor -ne 1) { throw 'WRONG_OS' }
  $base=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
  $bin=Join-Path $base 'bin'
  $script=Join-Path $bin 'onec-system-probe-poll.ps1'
  $curl=Join-Path $bin 'curl.exe'
  $ca=Join-Path $bin 'curl-ca-bundle.crt'
  $endpoint=Join-Path (Join-Path $base 'config') 'endpoint.txt'
  $token=Join-Path (Join-Path $base 'secrets') 'agent-token.machine.dpapi'
  $state=Join-Path $base 'state'
  foreach($p in @($script,$curl,$ca,$endpoint,$token)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'STAGE_FILE_MISSING' }
    if ($p.Contains('"') -or $p.Contains([char]10) -or $p.Contains([char]13)) { throw 'BAD_FILE_PATH' }
  }
  if (-not (Test-Path -LiteralPath $state -PathType Container)) { throw 'STATE_DIR_MISSING' }
  $scriptText=[IO.File]::ReadAllText($script,[Text.Encoding]::UTF8)
  if (-not $scriptText.StartsWith('#requires -version 2') -or
      -not $scriptText.Contains("S-1-5-19") -or
      -not $scriptText.Contains("DataProtectionScope]::LocalMachine")) {
    throw 'SYSTEM_SCRIPT_INVALID'
  }
  $address=[IO.File]::ReadAllText($endpoint,[Text.Encoding]::ASCII).Trim()
  if ($address -notmatch '^https://[a-z0-9-]+\.tail[a-z0-9-]+\.ts\.net:8443$') {
    throw 'ENDPOINT_INVALID'
  }
  $phase='CHECK_EXISTING_TASKS'
  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $root=$service.GetFolder('\')
  $user=$root.GetTask('MspOnecHttpsAgentProbe')
  if ($null -eq $user -or -not $user.Enabled) { throw 'LEGACY_TASK_NOT_ENABLED' }
  foreach($existing in $root.GetTasks(0)) {
    if ($existing.Name -eq $name) { throw 'SYSTEM_TASK_ALREADY_EXISTS' }
  }
  $sid=New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19'
  $localServiceAccount=$sid.Translate([Security.Principal.NTAccount]).Value
  if (-not $localServiceAccount) { throw 'LOCAL_SERVICE_UNRESOLVED' }

  $phase='DEFINE_MANUAL_ONLY_SYSTEM_TASK'
  $definition=$service.NewTask(0)
  $definition.RegistrationInfo.Description='MSP 1C LocalService outbound probe. Manual-only until cutover. No 1C reads or writes.'
  $definition.Principal.UserId=$localServiceAccount
  $definition.Principal.LogonType=5
  $definition.Principal.RunLevel=0
  $settings=$definition.Settings
  $settings.Enabled=$true
  $settings.AllowDemandStart=$true
  $settings.StartWhenAvailable=$false
  $settings.MultipleInstances=2
  $settings.ExecutionTimeLimit='PT2M'
  $settings.DisallowStartIfOnBatteries=$false
  $settings.StopIfGoingOnBatteries=$false

  $trigger=$definition.Triggers.Create(2)
  $trigger.StartBoundary=(Get-Date).AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ss')
  $trigger.DaysInterval=1
  $trigger.Repetition.Interval='PT1M'
  $trigger.Repetition.Duration='P1D'
  $trigger.Repetition.StopAtDurationEnd=$false
  $trigger.Enabled=$false

  $action=$definition.Actions.Create(0)
  $action.Path=(Join-Path $PSHOME 'powershell.exe')
  $action.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
    $script+'" -CurlExe "'+$curl+'" -CaBundle "'+$ca+'"')

  $phase='REGISTER_MANUAL_ONLY_SYSTEM_TASK'
  $task=$root.RegisterTaskDefinition($name,$definition,2,$localServiceAccount,$null,5,$null)
  $registered=$true
  if ($null -eq $task) { throw 'SYSTEM_TASK_CREATION_FAILED' }
  $phase='VERIFY_MANUAL_ONLY_SYSTEM_TASK'
  $actual=$root.GetTask($name)
  $d=$actual.Definition
  $principalSid=''
  try {
    $principalSid=(New-Object Security.Principal.NTAccount -ArgumentList $d.Principal.UserId).Translate([Security.Principal.SecurityIdentifier]).Value
  } catch {
    throw 'SYSTEM_TASK_PRINCIPAL_UNVERIFIED'
  }
  if ($principalSid -ne 'S-1-5-19') { throw 'SYSTEM_TASK_PRINCIPAL_UNVERIFIED' }
  if (-not $actual.Enabled -or $d.Principal.LogonType -ne 5 -or
      $d.Principal.RunLevel -ne 0 -or $d.Triggers.Count -ne 1 -or
      $d.Triggers.Item(1).Enabled -or $d.Actions.Count -ne 1 -or
      $d.Actions.Item(1).Path -ne (Join-Path $PSHOME 'powershell.exe')) {
    throw 'SYSTEM_TASK_DEFINITION_MISMATCH'
  }
  if (-not $root.GetTask('MspOnecHttpsAgentProbe').Enabled) {
    throw 'LEGACY_TASK_CHANGED'
  }
  Write-Output 'ONEC_SYSTEM_TASK_REGISTER'
  Write-Output 'RUN_AS_LOCAL_SERVICE=YES'
  Write-Output 'PASSWORD_REQUIRED=NO'
  Write-Output 'HIGHEST_PRIVILEGES=NO'
  Write-Output 'TASK_REGISTERED=YES'
  Write-Output 'MANUAL_EXECUTION_ALLOWED=YES'
  Write-Output 'AUTOMATIC_TRIGGER_ENABLED=NO'
  Write-Output 'OLD_AGENT_ENABLED=YES'
  Write-Output 'SYSTEM_AGENT_EXECUTION=NOT_YET_TESTED'
  Write-Output 'RESULT=PASS'
} catch {
  $reason=$_.Exception.Message
  $allow=@('WRONG_MACHINE','WRONG_OPERATOR','ADMIN_REQUIRED','WRONG_OS',
    'STAGE_FILE_MISSING','STATE_DIR_MISSING','BAD_FILE_PATH','SYSTEM_SCRIPT_INVALID',
    'ENDPOINT_INVALID','LEGACY_TASK_NOT_ENABLED','SYSTEM_TASK_ALREADY_EXISTS',
    'LOCAL_SERVICE_UNRESOLVED','SYSTEM_TASK_CREATION_FAILED',
    'SYSTEM_TASK_DEFINITION_MISMATCH','SYSTEM_TASK_PRINCIPAL_UNVERIFIED','LEGACY_TASK_CHANGED')
  if ($allow -notcontains $reason) { $reason='SCHEDULER_COM_FAILURE' }
  Write-Output ('RESULT=FAIL;STAGE=REGISTER_SYSTEM_TASK;GATE='+$reason)
  Write-Output ('FAILURE_PHASE='+$phase)
  if ($registered -and $null -ne $root) {
    try {
      $root.DeleteTask($name,0)
      Write-Output 'NEW_SYSTEM_TASK_ROLLBACK=COMPLETE'
    } catch {
      Write-Output 'NEW_SYSTEM_TASK_ROLLBACK=NEEDS_INSPECTION'
    }
  } else {
    Write-Output 'NEW_SYSTEM_TASK_REGISTERED=NOT_CONFIRMED'
  }
  exit 1
}

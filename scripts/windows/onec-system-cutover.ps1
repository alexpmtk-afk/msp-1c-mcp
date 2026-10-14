#requires -version 2
# Single-process controlled migration from personal polling to LocalService.
# Safe fixed probe only. On any rejection, restore the personal poller.
param(
  [Parameter(Mandatory=$true)][string]$ExpectedComputerName,
  [Parameter(Mandatory=$true)][string]$ExpectedAccount
)
$ErrorActionPreference='Stop'
$oldName='MspOnecHttpsAgentProbe'
$newName='MspOnecHttpsAgentSystem'
$root=$null
$oldChanged=$false
$newChangeAttempted=$false
$accepted=$false
$phase='PRECHECK'
function SidOf([string]$name) {
  try {
    return (New-Object Security.Principal.NTAccount -ArgumentList $name).Translate(
      [Security.Principal.SecurityIdentifier]).Value
  } catch { return '' }
}
function RegisterSystem([bool]$enable) {
  $present=$root.GetTask($newName)
  $def=$present.Definition
  if ($def.Principal.LogonType -ne 5 -or $def.Principal.RunLevel -ne 0 -or
      (SidOf $def.Principal.UserId) -ne 'S-1-5-19' -or
      $def.Triggers.Count -ne 1 -or $def.Actions.Count -ne 1) {
    throw 'SYSTEM_DEFINITION_MISMATCH'
  }
  $trigger=$def.Triggers.Item(1)
  $trigger.Enabled=$enable
  if ($enable) {
    # Old disabled trigger may not get an immediate first run until re-registered.
    $trigger.StartBoundary=(Get-Date).AddSeconds(30).ToString('yyyy-MM-ddTHH:mm:ss')
    $trigger.DaysInterval=1
    $trigger.Repetition.Interval='PT1M'
    $trigger.Repetition.Duration='P1D'
    $trigger.Repetition.StopAtDurationEnd=$false
  }
  $account=$def.Principal.UserId
  [void]$root.RegisterTaskDefinition($newName,$def,6,$account,$null,5,$null)
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  if ($id.Name -ne $ExpectedAccount) { throw 'WRONG_ACCOUNT' }
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $id
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  if ([Environment]::OSVersion.Version.Major -ne 6 -or
      [Environment]::OSVersion.Version.Minor -ne 1 -or
      $PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_HOST_VERSION' }
  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $root=$service.GetFolder('\')
  $old=$root.GetTask($oldName)
  $new=$root.GetTask($newName)
  if (-not $old.Enabled) { throw 'OLD_TASK_NOT_ENABLED' }
  if (-not $new.Enabled) { throw 'NEW_TASK_NOT_ENABLED' }
  if ($new.Definition.Triggers.Count -ne 1 -or
      $new.Definition.Triggers.Item(1).Enabled -or
      $new.Definition.Principal.LogonType -ne 5 -or
      (SidOf $new.Definition.Principal.UserId) -ne 'S-1-5-19') {
    throw 'NEW_TASK_NOT_MANUAL_ONLY'
  }
  $base=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
  $health=Join-Path (Join-Path $base 'state') 'last-status.txt'
  foreach($f in @((Join-Path (Join-Path $base 'bin') 'onec-system-probe-poll.ps1'),
    (Join-Path (Join-Path $base 'secrets') 'agent-token.machine.dpapi'),
    (Join-Path (Join-Path $base 'config') 'endpoint.txt'))) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw 'SYSTEM_FILE_MISSING' }
  }
  $action=$new.Definition.Actions.Item(1)
  $expectedExe=Join-Path $PSHOME 'powershell.exe'
  if ($action.Path -ne $expectedExe -or
      -not $action.Arguments.Contains('onec-system-probe-poll.ps1') -or
      -not $action.Arguments.Contains((Join-Path $base 'bin'))) {
    throw 'SYSTEM_ACTION_UNEXPECTED'
  }

  Write-Output 'ONEC_SYSTEM_CUTOVER'
  Write-Output 'CUTOVER_PRECONDITIONS=PASS'
  $startedUtc=[DateTime]::UtcNow
  $startedLocal=Get-Date

  $phase='DISABLE_PERSONAL_TASK'
  $oldChanged=$true
  $old.Enabled=$false
  if ($root.GetTask($oldName).Enabled) { throw 'PERSONAL_DISABLE_NOT_PERSISTED' }
  Write-Output 'OLD_AGENT_ENABLED=NO'

  $phase='ENABLE_SYSTEM_TIMER'
  $newChangeAttempted=$true
  RegisterSystem $true
  $nowNew=$root.GetTask($newName)
  if (-not $nowNew.Enabled -or
      -not $nowNew.Definition.Triggers.Item(1).Enabled -or
      (SidOf $nowNew.Definition.Principal.UserId) -ne 'S-1-5-19') {
    throw 'SYSTEM_TIMER_NOT_ENABLED'
  }
  Write-Output 'SYSTEM_AUTOMATIC_TRIGGER_ENABLED=YES'
  Write-Output 'SYSTEM_TIMER_ACCEPTANCE=WAITING'

  $phase='VERIFY_SCHEDULED_LOCAL_SERVICE_HEARTBEAT'
  for($i=1;$i -le 75;$i++) {
    Start-Sleep -Seconds 2
    $task=$root.GetTask($newName)
    if (Test-Path -LiteralPath $health -PathType Leaf) {
      $file=Get-Item -LiteralPath $health
      $lastRun=$task.LastRunTime
      if ($file.LastWriteTimeUtc -ge $startedUtc -and
          $lastRun -ge $startedLocal.AddSeconds(-2)) {
        $h=[IO.File]::ReadAllText($health,[Text.Encoding]::ASCII).Trim()
        if ($h -match '^UTC=[0-9TZ:-]+;STATUS=(POLL_OK|PROBE_ACK)$') {
          $accepted=$true
          break
        }
        if ($h -match '^UTC=[0-9TZ:-]+;STATUS=FAIL$') {
          throw 'SYSTEM_POLL_FAILED'
        }
      }
    }
  }
  if (-not $accepted) { throw 'SCHEDULED_SYSTEM_HEARTBEAT_TIMEOUT' }
  $phase='VERIFY_FINAL_TASK_STATE'
  if ($root.GetTask($oldName).Enabled -or
      -not $root.GetTask($newName).Definition.Triggers.Item(1).Enabled) {
    throw 'FINAL_TASK_STATE_MISMATCH'
  }
  Write-Output 'SYSTEM_SCHEDULED_HEARTBEAT=PASS'
  Write-Output 'PERSONAL_AGENT_DISABLED=YES'
  Write-Output 'SYSTEM_AGENT_TIMER=ENABLED'
  Write-Output 'PROBE_ONLY=YES'
  Write-Output 'GITHUB_ROUNDTRIP=NOT_YET_TESTED'
  Write-Output 'RESULT=PASS'
} catch {
  $reason=$_.Exception.Message
  $known=@('WRONG_MACHINE','WRONG_ACCOUNT','ADMIN_REQUIRED',
    'WRONG_HOST_VERSION','OLD_TASK_NOT_ENABLED','NEW_TASK_NOT_ENABLED',
    'NEW_TASK_NOT_MANUAL_ONLY','SYSTEM_FILE_MISSING','SYSTEM_ACTION_UNEXPECTED',
    'PERSONAL_DISABLE_NOT_PERSISTED','SYSTEM_DEFINITION_MISMATCH',
    'SYSTEM_TIMER_NOT_ENABLED','SYSTEM_POLL_FAILED',
    'SCHEDULED_SYSTEM_HEARTBEAT_TIMEOUT','FINAL_TASK_STATE_MISMATCH')
  if ($known -notcontains $reason) { $reason='CUTOVER_FAILURE' }
  Write-Output ('RESULT=FAIL;STAGE=SYSTEM_CUTOVER;GATE='+$reason)
  Write-Output ('FAILURE_PHASE='+$phase)
  if ($oldChanged -and $null -ne $root) {
    # Restore old FIRST to avoid a gap, then disarm the new timer.
    try {
      $root.GetTask($oldName).Enabled=$true
      if ($root.GetTask($oldName).Enabled) {
        Write-Output 'PERSONAL_AGENT_RESTORE=PASS'
      } else {
        Write-Output 'PERSONAL_AGENT_RESTORE=NOT_CONFIRMED'
      }
    } catch { Write-Output 'PERSONAL_AGENT_RESTORE=FAILED' }
  }
  if ($newChangeAttempted -and $null -ne $root) {
    try {
      RegisterSystem $false
      if (-not $root.GetTask($newName).Definition.Triggers.Item(1).Enabled) {
        Write-Output 'SYSTEM_TIMER_DISARM=PASS'
      } else {
        Write-Output 'SYSTEM_TIMER_DISARM=NOT_CONFIRMED'
      }
    } catch { Write-Output 'SYSTEM_TIMER_DISARM=FAILED' }
  }
  exit 1
}

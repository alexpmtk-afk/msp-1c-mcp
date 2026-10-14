#requires -version 2
# Controlled one-shot runtime acceptance of the manual-only LocalService task.
# No timers enabled, no task setting changes, no OData or arbitrary commands.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$taskName='MspOnecHttpsAgentSystem'
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $root=$service.GetFolder('\')
  $task=$root.GetTask($taskName)
  $def=$task.Definition
  if (-not $task.Enabled -or $def.Principal.LogonType -ne 5 -or
      $def.Principal.RunLevel -ne 0 -or $def.Triggers.Count -ne 1 -or
      $def.Triggers.Item(1).Enabled -or $def.Actions.Count -ne 1) {
    throw 'SYSTEM_TASK_NOT_MANUAL_ONLY'
  }
  $principalSid=''
  try {
    $principalSid=(New-Object Security.Principal.NTAccount -ArgumentList $def.Principal.UserId).Translate([Security.Principal.SecurityIdentifier]).Value
  } catch {
    throw 'SYSTEM_TASK_NOT_LOCAL_SERVICE'
  }
  if ($principalSid -ne 'S-1-5-19') { throw 'SYSTEM_TASK_NOT_LOCAL_SERVICE' }
  $old=$root.GetTask('MspOnecHttpsAgentProbe')
  if (-not $old.Enabled) { throw 'LEGACY_TASK_NOT_ENABLED' }
  $base=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
  $statusFile=Join-Path (Join-Path $base 'state') 'last-status.txt'
  $started=[DateTime]::UtcNow
  $running=$task.Run($null)
  if ($null -eq $running) { throw 'RUN_RETURNED_EMPTY' }
  Write-Output 'ONEC_SYSTEM_TASK_MANUAL_SMOKE'
  Write-Output 'MANUAL_START=ACCEPTED'
  Write-Output 'AUTOMATIC_TRIGGER_ENABLED=NO'
  Write-Output 'OLD_AGENT_ENABLED=YES'
  $found=$false
  $health='NOT_RECEIVED'
  for($i=1;$i -le 40;$i++) {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $statusFile -PathType Leaf) {
      $file=Get-Item -LiteralPath $statusFile
      if ($file.LastWriteTimeUtc -ge $started) {
        $line=[IO.File]::ReadAllText($statusFile,[Text.Encoding]::ASCII).Trim()
        if ($line -match '^UTC=[0-9TZ:-]+;STATUS=(POLL_OK|PROBE_ACK|FAIL)$') {
          $health=$Matches[1];$found=$true;break
        } else {
          $health='UNRECOGNIZED_STATUS';break
        }
      }
    }
  }
  Write-Output ('LOCAL_SERVICE_HEALTH='+$health)
  if ($found -and ($health -eq 'POLL_OK' -or $health -eq 'PROBE_ACK')) {
    Write-Output 'SYSTEM_TASK_RUNTIME=PASS'
    Write-Output 'RESULT=PASS'
  } else {
    Write-Output 'SYSTEM_TASK_RUNTIME=NOT_ACCEPTED'
    Write-Output 'RESULT=FAIL;GATE=SYSTEM_TASK_HEALTH'
    exit 1
  }
} catch {
  $reason=$_.Exception.Message
  $allowed=@('WRONG_MACHINE','ADMIN_REQUIRED','SYSTEM_TASK_NOT_MANUAL_ONLY',
    'LEGACY_TASK_NOT_ENABLED','SYSTEM_TASK_NOT_LOCAL_SERVICE','RUN_RETURNED_EMPTY')
  if ($allowed -notcontains $reason) { $reason='MANUAL_SMOKE_FAILURE' }
  Write-Output ('RESULT=FAIL;STAGE=MANUAL_SYSTEM_SMOKE;GATE='+$reason)
  exit 1
}

#requires -version 2
# Read-only status check; no need for administrator rights to run.
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
try {
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $task=$scheduler.GetFolder('\').GetTask('MspBitrix24Bridge')
  $runAs=$task.Definition.Principal.UserId
  $triggerCount=$task.Definition.Triggers.Count
  $f=Join-Path $root 'state\status.txt'
  $status='MISSING'
  if (Test-Path -LiteralPath $f) {
    $status=[IO.File]::ReadAllText($f,[Text.Encoding]::ASCII).Trim()
    if ($status.Length -gt 256) { $status='INVALID_STATUS_SIZE' }
  }
  'SYSTEM_TASK_EXISTS=YES'
  'RUN_AS_LOCAL_SERVICE='+($runAs -match '(?i)local.service|s-1-5-19')
  'TRIGGERS='+$triggerCount
  'LAST_STATUS='+$status
  'RESULT=PASS;STAGE=BITRIX24_STATUS'
} catch {
  'RESULT=FAIL;STAGE=BITRIX24_STATUS;GATE=TASK_UNAVAILABLE'
}

#requires -version 2
# Read-only verification of the one fixed Task Scheduler task. No secrets printed.
param([string]$TaskName='MspOnecHttpsAgentProbe')
$ErrorActionPreference='Stop'
try {
  if ($TaskName -ne 'MspOnecHttpsAgentProbe') { throw 'INVALID_TASK' }
  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $task=$service.GetFolder('\').GetTask($TaskName)
  if ($null -eq $task) { throw 'TASK_MISSING' }
  $logon=$task.Definition.Principal.LogonType
  $level=$task.Definition.Principal.RunLevel
  $interval=$task.Definition.Triggers.Item(1).Repetition.Interval
  $lastResult=$task.LastTaskResult
  $lastTime=$task.LastRunTime
  $recent=$false
  if ($null -ne $lastTime -and $lastTime.Year -gt 2000) {
    $recent=((Get-Date)-$lastTime).TotalMinutes -ge 0 -and
      ((Get-Date)-$lastTime).TotalMinutes -le 5
  }
  Write-Output 'ONEC_SRV_TASK_STATUS'
  Write-Output ('ENABLED='+$(if($task.Enabled){'YES'}else{'NO'}))
  Write-Output ('PASSWORD_LOGON='+$(if($logon -eq 1){'YES'}else{'NO'}))
  Write-Output ('NON_ELEVATED='+$(if($level -eq 0){'YES'}else{'NO'}))
  Write-Output ('EVERY_MINUTE='+$(if($interval -eq 'PT1M'){'YES'}else{'NO'}))
  Write-Output ('RECENT_EXECUTION='+$(if($recent){'YES'}else{'NO'}))
  Write-Output ('LAST_RESULT_ZERO='+$(if($lastResult -eq 0){'YES'}else{'NO'}))
  if ($task.Enabled -and $logon -eq 1 -and $level -eq 0 -and $interval -eq 'PT1M' -and $recent -and $lastResult -eq 0) {
    Write-Output 'RESULT=PASS'
  } else {
    Write-Output 'RESULT=NOT_YET_ACCEPTED'
  }
} catch {
  Write-Output 'RESULT=FAIL;GATE=TASK_NOT_READABLE'
  exit 1
}

#requires -version 2
# Safe rollback: remove ONLY the dedicated unattended 1C probe task.
# Does not touch tokens, OData/IIS, production 1C, or other scheduled tasks.
$ErrorActionPreference='Stop'
try {
  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $root=$service.GetFolder('\')
  $taskName='MspOnecHttpsAgentProbe'
  $task=$root.GetTask($taskName)
  $account=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ($task.Definition.Principal.UserId -ne $account) { throw 'WRONG_OWNER' }
  $root.DeleteTask($taskName,0)
  Write-Output 'RESULT=PASS;STAGE=SCHEDULE_REMOVED;DPAPI_UNCHANGED=YES'
} catch {
  Write-Output 'RESULT=FAIL;STAGE=SCHEDULE_REMOVE'
  exit 1
}

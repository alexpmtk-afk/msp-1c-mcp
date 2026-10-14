#requires -version 2
# Emergency operator rollback: re-enable personal task FIRST; disable LocalService timer.
# No changes to installed files, tokens, 1C, VPS or unrelated tasks.
param(
 [Parameter(Mandatory=$true)][string]$ExpectedComputerName,
 [Parameter(Mandatory=$true)][string]$ExpectedAccount
)
$ErrorActionPreference='Stop'
try {
 if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
 $w=[Security.Principal.WindowsIdentity]::GetCurrent()
 if ($w.Name -ne $ExpectedAccount) { throw 'WRONG_ACCOUNT' }
 $p=New-Object Security.Principal.WindowsPrincipal -ArgumentList $w
 if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ADMIN_REQUIRED' }
 $s=New-Object -ComObject 'Schedule.Service'
 $s.Connect()
 $folder=$s.GetFolder('\')
 $old=$folder.GetTask('MspOnecHttpsAgentProbe')
 $system=$folder.GetTask('MspOnecHttpsAgentSystem')
 if (-not $old.Enabled) { $old.Enabled=$true }
 if (-not $folder.GetTask('MspOnecHttpsAgentProbe').Enabled) {
   throw 'PERSONAL_TASK_RESTORE_FAILED'
 }
 Write-Output 'PERSONAL_AGENT_RESTORE=PASS'
 $def=$system.Definition
 if ($def.Principal.LogonType -ne 5 -or $def.Triggers.Count -ne 1 -or
   $def.Principal.RunLevel -ne 0) { throw 'SYSTEM_DEFINITION_MISMATCH' }
 if ($def.Triggers.Item(1).Enabled) {
   $def.Triggers.Item(1).Enabled=$false
   [void]$folder.RegisterTaskDefinition('MspOnecHttpsAgentSystem',$def,6,
     $def.Principal.UserId,$null,5,$null)
 }
 if ($folder.GetTask('MspOnecHttpsAgentSystem').Definition.Triggers.Item(1).Enabled) {
   throw 'SYSTEM_TIMER_STILL_ENABLED'
 }
 Write-Output 'SYSTEM_TIMER_DISARM=PASS'
 Write-Output 'RESULT=PASS;STAGE=ROLLBACK_TO_PERSONAL_AGENT'
} catch {
 $known=@('WRONG_MACHINE','WRONG_ACCOUNT','ADMIN_REQUIRED',
  'PERSONAL_TASK_RESTORE_FAILED','SYSTEM_DEFINITION_MISMATCH','SYSTEM_TIMER_STILL_ENABLED')
 $reason=$_.Exception.Message
 if ($known -notcontains $reason) { $reason='MANUAL_ROLLBACK_FAILED' }
 Write-Output ('RESULT=FAIL;GATE='+$reason)
 exit 1
}

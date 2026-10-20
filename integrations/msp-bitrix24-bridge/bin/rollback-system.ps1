#requires -version 2
# Disable only this integration task; do not delete state, credentials or other MSP tasks.
param([string]$ExpectedComputerName='SRV',[switch]$ConfirmDisable)
$ErrorActionPreference='Stop'
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName -or -not $ConfirmDisable) { throw 'NO_APPROVAL' }
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  $p=New-Object Security.Principal.WindowsPrincipal -ArgumentList @($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ADMIN_REQUIRED' }
  $s=New-Object -ComObject Schedule.Service;$s.Connect()
  $t=$s.GetFolder('\').GetTask('MspBitrix24Bridge')
  $t.Enabled=$false
  'BRIDGE_TASK_DISABLED=YES'
  'PROGRAM_FILES_PRESERVED=YES'
  'SECRETS_PRESERVED=YES'
  'EXISTING_MSP_TASKS_UNCHANGED=YES'
  'RESULT=PASS;STAGE=BITRIX24_ROLLBACK'
} catch { 'RESULT=FAIL;STAGE=BITRIX24_ROLLBACK' }

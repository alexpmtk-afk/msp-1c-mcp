#requires -version 2
# Separately activate boot and 5-minute triggers ONLY after fresh, native LocalService smoke.
param([string]$ExpectedComputerName='SRV',[switch]$ConfirmEnable)
$ErrorActionPreference='Stop'
function Fail([string]$Reason){Write-Output ('RESULT=FAIL;STAGE=BITRIX24_ENABLE;GATE='+$Reason);exit 1}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName -or -not $ConfirmEnable){Fail 'APPROVAL_REQUIRED'}
  $p=New-Object Security.Principal.WindowsPrincipal -ArgumentList @([Security.Principal.WindowsIdentity]::GetCurrent())
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
  $s=New-Object -ComObject Schedule.Service;$s.Connect()
  $folder=$s.GetFolder('\');$task=$folder.GetTask('MspBitrix24Bridge');$d=$task.Definition
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList @($d.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
  if($sid -ne 'S-1-5-19' -or $d.Principal.LogonType -ne 5){Fail 'WRONG_IDENTITY'}
  if($d.Triggers.Count -ne 2 -or $d.Triggers.Item(1).Type -ne 8 -or $d.Triggers.Item(2).Type -ne 2){Fail 'WRONG_TRIGGERS'}
  if($d.Actions.Count -ne 1){Fail 'WRONG_ACTIONS'}
  $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
  if(-not $d.Actions.Item(1).Arguments.Contains((Join-Path $root 'bin\bridge.ps1'))){Fail 'WRONG_ENTRYPOINT'}
  $cfg=[IO.File]::ReadAllText((Join-Path $root 'config\bridge.ini'),[Text.Encoding]::ASCII)
  foreach($key in @('ACTIVE','CUSTOMERS_READ','PRODUCTS_READ','INVOICES_WRITE')){
    if($cfg -notmatch ('(?m)^'+$key+'=0$')){Fail 'UNSAFE_POLICY'}
  }
  $val=[IO.File]::ReadAllText((Join-Path $root 'state\status.txt'),[Text.Encoding]::ASCII).Trim()
  if($val -notmatch '^UTC=([^;]+);STATUS=SAFE_IDLE;IDENTITY=LOCAL_SERVICE;CUSTOMERS_SYNC=OFF;WRITES=OFF$'){Fail 'NO_VALID_SMOKE'}
  $when=[DateTime]::Parse($Matches[1]).ToUniversalTime()
  if($when -lt [DateTime]::UtcNow.AddMinutes(-5) -or $when -gt [DateTime]::UtcNow.AddSeconds(5)){Fail 'STALE_SMOKE'}
  $d.Triggers.Item(1).Enabled=$true
  $d.Triggers.Item(2).Enabled=$true
  $null=$folder.RegisterTaskDefinition('MspBitrix24Bridge',$d,6,'NT AUTHORITY\LOCAL SERVICE',$null,5,$null)
  $check=$folder.GetTask('MspBitrix24Bridge')
  if(-not $check.Definition.Triggers.Item(1).Enabled -or -not $check.Definition.Triggers.Item(2).Enabled){Fail 'ENABLE_NOT_CONFIRMED'}
  'RUN_AS_LOCAL_SERVICE=YES'
  'BOOT_TRIGGER_ENABLED=YES'
  'FIVE_MINUTE_TRIGGER_ENABLED=YES'
  'CUSTOMERS_SYNC=OFF'
  'ONEC_WRITES=OFF'
  'OTHER_MSP_TASKS_UNCHANGED=YES'
  'RESULT=PASS;STAGE=BITRIX24_ENABLED'
}catch{Fail 'ENABLE_ERROR'}

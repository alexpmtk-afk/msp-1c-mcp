#requires -version 2
# Stage new machine-owned task; automatic triggers remain disabled until separate acceptance.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
function Fail([string]$Reason){Write-Output ('RESULT=FAIL;STAGE=BITRIX24_STAGE;GATE='+$Reason);exit 1}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  $p=New-Object Security.Principal.WindowsPrincipal -ArgumentList @([Security.Principal.WindowsIdentity]::GetCurrent())
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
  $bin=Split-Path -Parent $MyInvocation.MyCommand.Path
  $src=Split-Path -Parent $bin
  $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
  $f=Join-Path $src 'bin\bridge.ps1'
  $c=Join-Path $src 'config\bridge.ini'
  if(-not (Test-Path -LiteralPath $f -PathType Leaf) -or -not (Test-Path -LiteralPath $c -PathType Leaf)){Fail 'STAGING_FILES_MISSING'}
  $policy=[IO.File]::ReadAllText($c,[Text.Encoding]::ASCII)
  foreach($key in @('ACTIVE','CUSTOMERS_READ','PRODUCTS_READ','INVOICES_WRITE')){
    if($policy -notmatch ('(?m)^'+$key+'=0$')){Fail 'UNSAFE_POLICY'}
  }
  $s=New-Object -ComObject Schedule.Service;$s.Connect();$folder=$s.GetFolder('\')
  try{$existing=$folder.GetTask('MspBitrix24Bridge')}catch{$existing=$null}
  if($null -ne $existing){Fail 'TASK_EXISTS'}
  if(Test-Path -LiteralPath $root){Fail 'ROOT_EXISTS'}
  foreach($name in @('bin','config','state','secrets','logs')){
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $root $name))
  }
  Copy-Item -LiteralPath $f -Destination (Join-Path $root 'bin\bridge.ps1') -ErrorAction Stop
  Copy-Item -LiteralPath $c -Destination (Join-Path $root 'config\bridge.ini') -ErrorAction Stop
  & icacls.exe $root '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-19:(OI)(CI)RX' '/T' | Out-Null
  if($LASTEXITCODE -ne 0){Fail 'ACL_ROOT_FAILED'}
  & icacls.exe (Join-Path $root 'state') '/grant:r' '*S-1-5-19:(OI)(CI)M' '/T' | Out-Null
  if($LASTEXITCODE -ne 0){Fail 'ACL_STATE_FAILED'}
  $d=$s.NewTask(0)
  $d.RegistrationInfo.Description='MSP Bitrix24 bridge: independent SAFE_IDLE (staged only)'
  $d.Principal.UserId='NT AUTHORITY\LOCAL SERVICE'
  $d.Principal.LogonType=5
  $d.Principal.RunLevel=0
  $d.Settings.Enabled=$true
  $d.Settings.StartWhenAvailable=$true
  $d.Settings.ExecutionTimeLimit='PT2M'
  $d.Settings.MultipleInstances=2
  $boot=$d.Triggers.Create(8);$boot.Enabled=$false
  $daily=$d.Triggers.Create(2);$daily.Enabled=$false
  $daily.DaysInterval=1
  $daily.StartBoundary=(Get-Date).ToString('yyyy-MM-ddT00:00:00')
  $daily.Repetition.Interval='PT5M'
  $daily.Repetition.Duration='P1D'
  $daily.Repetition.StopAtDurationEnd=$false
  $a=$d.Actions.Create(0)
  $a.Path=(Join-Path $PSHOME 'powershell.exe')
  $a.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $root 'bin\bridge.ps1')+'"')
  $null=$folder.RegisterTaskDefinition('MspBitrix24Bridge',$d,2,'NT AUTHORITY\LOCAL SERVICE',$null,5,$null)
  $registered=$folder.GetTask('MspBitrix24Bridge')
  if($registered.Definition.Triggers.Item(1).Enabled -or $registered.Definition.Triggers.Item(2).Enabled){Fail 'TRIGGERS_NOT_DISABLED'}
  'RUN_AS_LOCAL_SERVICE=YES'
  'BOOT_TRIGGER_ENABLED=NO'
  'FIVE_MINUTE_TRIGGER_ENABLED=NO'
  'MANUAL_EXECUTION_ALLOWED=YES'
  'CUSTOMERS_SYNC=OFF'
  'ONEC_WRITES=OFF'
  'OTHER_MSP_TASKS_UNCHANGED=YES'
  'RESULT=PASS;STAGE=BITRIX24_STAGED'
}catch{Fail 'STAGING_ERROR'}

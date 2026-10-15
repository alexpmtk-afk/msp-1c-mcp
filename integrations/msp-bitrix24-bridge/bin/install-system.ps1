#requires -version 2
# Explicit local administrator action only. Does NOT touch existing MSP agent.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
function StopInstall([string]$Reason) { Write-Output ('RESULT=FAIL;STAGE=BITRIX24_INSTALL;GATE='+$Reason); exit 1 }
if ($env:COMPUTERNAME -ne $ExpectedComputerName) { StopInstall 'WRONG_HOST' }
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal $id
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { StopInstall 'ADMIN_REQUIRED' }
$src=Split-Path -Parent $MyInvocation.MyCommand.Path
$src=Split-Path -Parent $src
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
try {
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $taskExists=$false
  try { $null=$folder.GetTask('MspBitrix24Bridge');$taskExists=$true } catch {}
  if ($taskExists -or (Test-Path -LiteralPath $root)) { StopInstall 'ALREADY_STAGED' }
  foreach($p in @('bin','config','state','secrets','logs')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root $p) | Out-Null
  }
  Copy-Item -LiteralPath (Join-Path $src 'bin\bridge.ps1') -Destination (Join-Path $root 'bin\bridge.ps1') -ErrorAction Stop
  Copy-Item -LiteralPath (Join-Path $src 'config\bridge.ini') -Destination (Join-Path $root 'config\bridge.ini') -ErrorAction Stop
  & icacls.exe $root '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-19:(OI)(CI)RX' '/T' | Out-Null
  if ($LASTEXITCODE -ne 0) { StopInstall 'ACL_ROOT_FAILED' }
  & icacls.exe (Join-Path $root 'state') '/grant:r' '*S-1-5-19:(OI)(CI)M' '/T' | Out-Null
  if ($LASTEXITCODE -ne 0) { StopInstall 'ACL_STATE_FAILED' }
  $def=$scheduler.NewTask(0)
  $def.RegistrationInfo.Description='MSP Bitrix24 standalone local bridge; SAFE_IDLE bootstrap'
  $def.Principal.UserId='NT AUTHORITY\LOCAL SERVICE'
  $def.Principal.LogonType=5
  $def.Principal.RunLevel=0
  $def.Settings.Enabled=$true
  $def.Settings.Hidden=$false
  $def.Settings.StartWhenAvailable=$true
  $def.Settings.ExecutionTimeLimit='PT2M'
  $def.Settings.MultipleInstances=2
  $boot=$def.Triggers.Create(8)
  $boot.Enabled=$true
  $daily=$def.Triggers.Create(2)
  $daily.Enabled=$true
  $daily.DaysInterval=1
  $daily.StartBoundary=(Get-Date).ToString('yyyy-MM-ddT00:00:00')
  $daily.Repetition.Interval='PT5M'
  $daily.Repetition.Duration='P1D'
  $daily.Repetition.StopAtDurationEnd=$false
  $action=$def.Actions.Create(0)
  $action.Path=(Join-Path $PSHOME 'powershell.exe')
  $action.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $root 'bin\bridge.ps1')+'"')
  $null=$folder.RegisterTaskDefinition('MspBitrix24Bridge',$def,2,'NT AUTHORITY\LOCAL SERVICE',$null,5,$null)
  'RUNTIME_ROOT='+$root
  'RUN_AS_LOCAL_SERVICE=YES'
  'BOOT_TRIGGER=YES'
  'REPEAT_EVERY_5_MINUTES=YES'
  'PERSONAL_ACCOUNT_REQUIRED=NO'
  'CUSTOMERS_SYNC=OFF'
  'ONEC_WRITES=OFF'
  'EXISTING_MSP_TASKS_UNCHANGED=YES'
  'RESULT=PASS;STAGE=BITRIX24_SYSTEM_REGISTERED'
} catch {
  StopInstall 'INSTALL_FAILED_REVIEW_STAGED_ROOT'
}

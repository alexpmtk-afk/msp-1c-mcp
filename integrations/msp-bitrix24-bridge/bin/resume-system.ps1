#requires -version 2
# Resume ONLY the observed partial Bitrix24 stage after missing icacls PATH.
# Expected state: five empty subfolders except bridge.ps1 and bridge.ini; no task.
# No edits to 1C, IIS, MSP, GitHub runner or Bitrix24.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='IDENTITY'
function Fail([string]$Reason) { throw ('BITRIX24_'+$Reason) }
function HashFile([string]$Path) {
  $sha=New-Object Security.Cryptography.SHA256Managed
  try {
    return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-','').ToLowerInvariant()
  } finally { $sha.Clear() }
}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $id
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
  $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
  $phase='RESOLVE_ICACLS'
  $icacls=Join-Path $env:WINDIR 'System32\icacls.exe'
  if(-not (Test-Path -LiteralPath $icacls -PathType Leaf)){$icacls=Join-Path $env:WINDIR 'Sysnative\icacls.exe'}
  if(-not (Test-Path -LiteralPath $icacls -PathType Leaf)){Fail 'ICACLS_MISSING'}
  $phase='VERIFY_PARTIAL_STAGE'
  if(-not (Test-Path -LiteralPath $root -PathType Container)){Fail 'ROOT_MISSING'}
  if((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint){Fail 'ROOT_REPARSE_POINT'}
  $sub=@('bin','config','state','secrets','logs')
  $entries=@(Get-ChildItem -LiteralPath $root -Force)
  if($entries.Count -ne 5){Fail 'UNEXPECTED_ROOT_ENTRIES'}
  foreach($n in $sub){
    $p=Join-Path $root $n
    if(-not (Test-Path -LiteralPath $p -PathType Container)){Fail 'EXPECTED_FOLDER_MISSING'}
    $o=Get-Item -LiteralPath $p
    if($o.Attributes -band [IO.FileAttributes]::ReparsePoint){Fail 'FOLDER_REPARSE_POINT'}
  }
  foreach($n in @('state','secrets','logs')){
    if(@(Get-ChildItem -LiteralPath (Join-Path $root $n) -Force).Count -ne 0){Fail 'UNEXPECTED_RUNTIME_CONTENTS'}
  }
  foreach($n in @('bin','config')){
    if(@(Get-ChildItem -LiteralPath (Join-Path $root $n) -Force).Count -ne 1){Fail 'UNEXPECTED_STAGED_FILES'}
  }
  $main=Join-Path $root 'bin\bridge.ps1'
  $config=Join-Path $root 'config\bridge.ini'
  if(-not (Test-Path -LiteralPath $main -PathType Leaf) -or -not (Test-Path -LiteralPath $config -PathType Leaf)){Fail 'STAGED_FILES_MISSING'}
  if((HashFile $main) -ne '22240335d75d8447d7beb99b7040935f1c6a53b7703019897f39c6263f2070ec'){Fail 'BRIDGE_FILE_HASH_MISMATCH'}
  if((HashFile $config) -ne 'e2599e2f9252b6368bb79b8ed60748a76a2489cc1b3e54c14182d0ba6e571175'){Fail 'POLICY_HASH_MISMATCH'}
  $phase='TASK_SCHEDULER_CONNECT'
  $s=New-Object -ComObject Schedule.Service
  $s.Connect()
  $folder=$s.GetFolder('\')
  $task=$null
  try{$task=$folder.GetTask('MspBitrix24Bridge')}catch{}
  if($null -ne $task){Fail 'TASK_ALREADY_EXISTS'}
  $sid=New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19'
  $svc=$sid.Translate([Security.Principal.NTAccount]).Value
  if(-not $svc){Fail 'LOCAL_SERVICE_NOT_FOUND'}
  $phase='APPLY_ROOT_ACL'
  & $icacls $root '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-19:(OI)(CI)RX' '/T' | Out-Null
  if($LASTEXITCODE -ne 0){Fail 'ACL_ROOT_FAILED'}
  $phase='APPLY_STATE_ACL'
  & $icacls (Join-Path $root 'state') '/grant:r' '*S-1-5-19:(OI)(CI)M' '/T' | Out-Null
  if($LASTEXITCODE -ne 0){Fail 'ACL_STATE_FAILED'}
  $phase='REGISTER_TASK'
  $d=$s.NewTask(0)
  $d.RegistrationInfo.Description='MSP Bitrix24 independent SAFE_IDLE; manual smoke required'
  $d.Principal.UserId=$svc
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
  $a.Path=Join-Path $PSHOME 'powershell.exe'
  $a.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$main+'"')
  $null=$folder.RegisterTaskDefinition('MspBitrix24Bridge',$d,2,$svc,$null,5,$null)
  $phase='VERIFY_TASK'
  $actual=$folder.GetTask('MspBitrix24Bridge')
  $aSid=(New-Object Security.Principal.NTAccount -ArgumentList $actual.Definition.Principal.UserId).Translate([Security.Principal.SecurityIdentifier]).Value
  if($aSid -ne 'S-1-5-19' -or $actual.Definition.Principal.LogonType -ne 5 -or
     $actual.Definition.Triggers.Count -ne 2 -or
     $actual.Definition.Triggers.Item(1).Enabled -or
     $actual.Definition.Triggers.Item(2).Enabled){Fail 'TASK_DEFINITION_MISMATCH'}
  'PARTIAL_STAGE_RECOVERY=PASS'
  'LOCAL_SERVICE_ACCOUNT=YES'
  'BOOT_TRIGGER_ENABLED=NO'
  'FIVE_MINUTE_TRIGGER_ENABLED=NO'
  'MANUAL_TEST_REQUIRED=YES'
  'CUSTOMERS_SYNC=OFF'
  'ONEC_WRITES=OFF'
  'RESULT=PASS;STAGE=BITRIX24_PARTIAL_RECOVERY'
} catch {
  $reason=$_.Exception.Message
  $gate='UNCLASSIFIED_ERROR'
  if($reason -match '^BITRIX24_([A-Z_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=BITRIX24_PARTIAL_RECOVERY;GATE='+$gate
  'FAILURE_PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

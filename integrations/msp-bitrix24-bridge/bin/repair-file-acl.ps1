#requires -version 2
# Surgical ACL repair after confirmed empty DACL on two Bitrix24 files.
# This program is NOT a task; manual elevated use on SRV only.
# No recursive flags, ownership changes, service modifications or 1C access.
param([string]$ExpectedComputerName='SRV',[switch]$ConfirmRepair)
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code) { throw ('BRIDGE_'+$Code) }
function HashFile([string]$Path) {
  $sha=New-Object Security.Cryptography.SHA256Managed
  try {
    return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-','').ToLowerInvariant()
  } finally { $sha.Clear() }
}
try {
  if(-not $ConfirmRepair){Fail 'EXPLICIT_APPROVAL_REQUIRED'}
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_COMPUTER'}
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
  if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
  $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
  if($root -ne 'C:\ProgramData\MspBitrix24Bridge'){Fail 'ROOT_MISMATCH'}
  if(-not (Test-Path -LiteralPath $root -PathType Container)){Fail 'ROOT_MISSING'}
  $icacls=Join-Path $env:WINDIR 'System32\icacls.exe'
  if(-not (Test-Path -LiteralPath $icacls -PathType Leaf)){$icacls=Join-Path $env:WINDIR 'Sysnative\icacls.exe'}
  if(-not (Test-Path -LiteralPath $icacls -PathType Leaf)){Fail 'ICACLS_MISSING'}
  $phase='GUARD_TASK'
  $s=New-Object -ComObject Schedule.Service;$s.Connect()
  $task=$s.GetFolder('\').GetTask('MspBitrix24Bridge')
  if($null -eq $task -or -not $task.Enabled){Fail 'TASK_MISSING_OR_DISABLED'}
  $taskUser=$task.Definition.Principal.UserId
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList $taskUser).Translate([Security.Principal.SecurityIdentifier]).Value
  if($sid -ne 'S-1-5-19'){Fail 'TASK_IDENTITY_MISMATCH'}
  if($task.Definition.Triggers.Count -ne 2 -or $task.Definition.Triggers.Item(1).Enabled -or $task.Definition.Triggers.Item(2).Enabled){Fail 'AUTOSTART_MUST_BE_OFF'}
  if($task.Definition.Actions.Count -ne 1){Fail 'ACTIONS_COUNT_MISMATCH'}
  $bridge=Join-Path $root 'bin\bridge.ps1'
  $policy=Join-Path $root 'config\bridge.ini'
  $action=$task.Definition.Actions.Item(1)
  $expectedArgs='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$bridge+'"'
  if($action.Arguments -cne $expectedArgs){Fail 'TASK_COMMAND_MISMATCH'}
  $phase='GUARD_FILES'
  foreach($dir in @($root,(Join-Path $root 'bin'),(Join-Path $root 'config'),(Join-Path $root 'state'))){
    if(-not (Test-Path -LiteralPath $dir -PathType Container)){Fail 'DIRECTORY_MISSING'}
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DIRECTORY'}
  }
  foreach($f in @($bridge,$policy)){
    if(-not (Test-Path -LiteralPath $f -PathType Leaf)){Fail 'FILE_MISSING'}
    if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  }
  $phase='REPAIR_TWO_FILE_DACLS'
  foreach($f in @($bridge,$policy)){
    & $icacls $f '/grant:r' '*S-1-5-18:F' '*S-1-5-32-544:F' '*S-1-5-19:RX' | Out-Null
    if($LASTEXITCODE -ne 0){Fail 'EXPLICIT_GRANT_FAILED'}
  }
  $phase='VERIFY_FILES'
  if((HashFile $bridge) -ne '22240335d75d8447d7beb99b7040935f1c6a53b7703019897f39c6263f2070ec'){Fail 'BRIDGE_HASH_MISMATCH'}
  if((HashFile $policy) -ne 'e2599e2f9252b6368bb79b8ed60748a76a2489cc1b3e54c14182d0ba6e571175'){Fail 'POLICY_HASH_MISMATCH'}
  foreach($f in @($bridge,$policy)){
    $acl=Get-Acl -LiteralPath $f
    foreach($targetSid in @('S-1-5-18','S-1-5-32-544','S-1-5-19')){
      $found=$false
      foreach($entry in $acl.Access){
        try {
          $aceSid=$entry.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
          if($aceSid -eq $targetSid -and $entry.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow){$found=$true}
        } catch {}
      }
      if(-not $found){Fail 'EXPECTED_ACE_MISSING'}
    }
  }
  'BRIDGE_SCRIPT_HASH=PASS'
  'POLICY_HASH=PASS'
  'FILES_REPAIRED=2'
  'ROOT_AND_OTHER_FILES_UNCHANGED=YES'
  'TASK_AUTOSTART=OFF'
  'LOCAL_SERVICE_ACCESS=RESTORED'
  'CUSTOMERS_SYNC=OFF'
  'ONEC_WRITES=OFF'
  'RESULT=PASS;STAGE=BITRIX24_FILE_ACL_REPAIR'
} catch {
  $msg=$_.Exception.Message
  $reason='LOCAL_REPAIR_EXCEPTION'
  if($msg -match '^BRIDGE_([A-Z_]+)$'){$reason=$Matches[1]}
  'RESULT=FAIL;STAGE=BITRIX24_FILE_ACL_REPAIR;GATE='+$reason
  'FAILURE_PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

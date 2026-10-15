#requires -version 2
# READ ONLY: registered Bitrix24 task, pinned file hash, ACL and scheduler event IDs.
# Never launches tasks, accesses 1C/Bitrix, exports log messages, or reads secrets.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName) {throw 'WRONG_HOST'}
  $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
  $main=Join-Path $root 'bin\bridge.ps1'
  $cfg=Join-Path $root 'config\bridge.ini'
  $state=Join-Path $root 'state'
  $s=New-Object -ComObject Schedule.Service
  $s.Connect()
  $t=$s.GetFolder('\').GetTask('MspBitrix24Bridge')
  $a=$t.Definition.Actions.Item(1)
  $expectedExe=Join-Path $PSHOME 'powershell.exe'
  $expectedArgs='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$main+'"'
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList @($t.Definition.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
  'TASK_LAST_RUN='+$t.LastRunTime.ToString('yyyy-MM-ddTHH:mm:ss')
  'TASK_LAST_RESULT='+$t.LastTaskResult
  'TASK_STATE='+$t.State
  'TASK_ENABLED='+$t.Enabled
  'TASK_IDENTITY_LOCAL_SERVICE='+($sid -eq 'S-1-5-19')
  'TASK_ACTIONS='+$t.Definition.Actions.Count
  'ACTION_EXE_EXPECTED='+($a.Path -ieq $expectedExe)
  'ACTION_FILE_ARGUMENT_EXPECTED='+($a.Arguments -ceq $expectedArgs)
  'BOOT_AUTO_ENABLED='+$t.Definition.Triggers.Item(1).Enabled
  'TIMER_AUTO_ENABLED='+$t.Definition.Triggers.Item(2).Enabled
  'SCRIPT_EXISTS='+(Test-Path -LiteralPath $main -PathType Leaf)
  'POLICY_EXISTS='+(Test-Path -LiteralPath $cfg -PathType Leaf)
  if(Test-Path -LiteralPath $main -PathType Leaf){
    $hash=New-Object Security.Cryptography.SHA256Managed
    try {
      $actual=[BitConverter]::ToString($hash.ComputeHash([IO.File]::ReadAllBytes($main))).Replace('-','').ToLowerInvariant()
      'SCRIPT_HASH_VALID='+($actual -eq '22240335d75d8447d7beb99b7040935f1c6a53b7703019897f39c6263f2070ec')
    } finally { $hash.Clear() }
  }
  if(Test-Path -LiteralPath $cfg -PathType Leaf){
    $hash=New-Object Security.Cryptography.SHA256Managed
    try {
      $actual=[BitConverter]::ToString($hash.ComputeHash([IO.File]::ReadAllBytes($cfg))).Replace('-','').ToLowerInvariant()
      'POLICY_HASH_VALID='+($actual -eq 'e2599e2f9252b6368bb79b8ed60748a76a2489cc1b3e54c14182d0ba6e571175')
    } finally { $hash.Clear() }
  }
  foreach($name in @('root','state')){
    $dir=$root
    if($name -eq 'state'){$dir=$state}
    if(Test-Path -LiteralPath $dir -PathType Container){
      $acl=Get-Acl -LiteralPath $dir
      'ACL_'+$name.ToUpper()+'_PROTECTED='+$acl.AreAccessRulesProtected
      $ls=@()
      foreach($entry in $acl.Access){
        try{
          $entrySid=$entry.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
          if($entrySid -eq 'S-1-5-19'){$ls+=($entry.AccessControlType.ToString()+':'+$entry.FileSystemRights.ToString())}
        }catch{}
      }
      'ACL_'+$name.ToUpper()+'_LOCAL_SERVICE='+($ls -join '|')
    }
  }
  'STATUS_PRESENT='+(Test-Path -LiteralPath (Join-Path $state 'status.txt') -PathType Leaf)
  'TMP_PRESENT='+(Test-Path -LiteralPath (Join-Path $state 'status.tmp') -PathType Leaf)
  $history=@()
  try {
    $events=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational';StartTime=(Get-Date).AddHours(-3)} -ErrorAction Stop)
    foreach($event in $events){
      if($event.Message -like '*MspBitrix24Bridge*'){
        $history+=('TASK_EVENT='+$event.TimeCreated.ToString('yyyy-MM-ddTHH:mm:ss')+';ID='+$event.Id)
        if($history.Count -ge 12){break}
      }
    }
  } catch { 'TASK_HISTORY_UNAVAILABLE=YES' }
  if($history.Count -eq 0){'TASK_HISTORY_MATCHES=0'}
  foreach($x in $history){$x}
  'NO_CHANGES=YES'
  'RESULT=PASS;STAGE=BITRIX24_RUNTIME_READONLY_DIAGNOSTIC'
} catch {
  'RESULT=FAIL;STAGE=BITRIX24_RUNTIME_READONLY_DIAGNOSTIC;GATE=READONLY_CHECK_ERROR'
}

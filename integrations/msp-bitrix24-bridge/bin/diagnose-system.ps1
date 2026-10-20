#requires -version 2
# Read-only post-install snapshot on SRV. No secrets, tokens, process arguments or customer data.
$ErrorActionPreference='Stop'
try {
  $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
  $windows=[Security.Principal.WindowsIdentity]::GetCurrent()
  $p=New-Object Security.Principal.WindowsPrincipal -ArgumentList $windows
  $admin=$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  'MACHINE_IS_SRV='+($env:COMPUTERNAME -eq 'SRV')
  'ADMIN_ELEVATED='+$admin
  'ROOT_EXISTS='+(Test-Path -LiteralPath $root -PathType Container)
  foreach($name in @('bin','config','state','secrets','logs')){
    'DIR_'+$name.ToUpper()+'='+(Test-Path -LiteralPath (Join-Path $root $name) -PathType Container)
  }
  'BRIDGE_FILE='+(Test-Path -LiteralPath (Join-Path $root 'bin\bridge.ps1') -PathType Leaf)
  'POLICY_FILE='+(Test-Path -LiteralPath (Join-Path $root 'config\bridge.ini') -PathType Leaf)
  'HEARTBEAT_PRESENT='+(Test-Path -LiteralPath (Join-Path $root 'state\status.txt') -PathType Leaf)
  $s=New-Object -ComObject Schedule.Service
  $s.Connect()
  $folder=$s.GetFolder('\')
  $task=$null
  try {$task=$folder.GetTask('MspBitrix24Bridge')} catch {}
  'BRIDGE_TASK_PRESENT='+($null -ne $task)
  if($null -ne $task) {
    'BRIDGE_TASK_ENABLED='+$task.Enabled
    'TRIGGER_COUNT='+$task.Definition.Triggers.Count
    $sid=''
    try {
      $name=$task.Definition.Principal.UserId
      $sid=(New-Object Security.Principal.NTAccount -ArgumentList $name).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch {}
    'RUN_AS_LOCAL_SERVICE='+($sid -eq 'S-1-5-19')
    if($task.Definition.Triggers.Count -ge 1){'TRIGGER_1_ENABLED='+$task.Definition.Triggers.Item(1).Enabled}
    if($task.Definition.Triggers.Count -ge 2){'TRIGGER_2_ENABLED='+$task.Definition.Triggers.Item(2).Enabled}
  }
  'NO_CHANGES=YES'
  'RESULT=PASS;STAGE=BITRIX24_READONLY_SNAPSHOT'
} catch {
  'RESULT=FAIL;STAGE=BITRIX24_READONLY_SNAPSHOT;GATE=INSPECTION_ERROR'
}

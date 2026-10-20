#requires -version 2
# Recover broken 14-line cmd for already registered MspNewBuyerDiagnosticV1.
# This operates only on diagnostic CMD and task; original discovery task, 1C and CRM untouched.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function Gate([string]$Why){throw ('RECOVERY_'+$Why)}
function Hash([string]$Path){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){Gate 'HOST_DENIED'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Gate 'PS2_X64_REQUIRED'}
 $p=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Gate 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore';$dir=Join-Path $root 'staging\msp-newbuyer-diagnostic-v1'
 $bat=Join-Path $dir 'start-diagnostic.cmd';$worker=Join-Path $dir 'diagnose-newbuyer-execution-v1.ps1'
 $stdout=Join-Path $root 'state\msp-newbuyer-diagnostic-v1.stdout.txt'
 $status=Join-Path $root 'state\msp-newbuyer-diagnostic-v1.status'
 $backup=Join-Path $dir 'start-diagnostic.cmd.before-fix-v2'
 $tmp=Join-Path $dir 'start-diagnostic.cmd.pending-v2'
 $ps=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $cmdexe=Join-Path $env:windir 'System32\cmd.exe'
 foreach($f in @($bat,$worker,$ps,$cmdexe)){
  if(-not [IO.File]::Exists($f)){Gate 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Gate 'REPARSE_DENIED'}
 }
 if([IO.File]::Exists($backup) -or [IO.File]::Exists($tmp) -or [IO.File]::Exists($stdout) -or [IO.File]::Exists($status)){Gate 'PREVIOUS_RECOVERY_OR_DIAGNOSTIC_EXISTS'}
 if((Hash $worker) -ne 'f9bc8f9ac65025b6b5d5eee6737f060e6ef00a2f72a5b4f41519d4693e16fe60'){Gate 'WORKER_HASH_CHANGED'}
 $err=$null;$null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$err)
 if($err -and $err.Count -gt 0){Gate 'WORKER_PARSE_FAILED'}
 $s=New-Object -ComObject Schedule.Service;$s.Connect();$folder=$s.GetFolder('\')
 $task=$folder.GetTask('MspNewBuyerDiagnosticV1')
 $original=$folder.GetTask('MspNewBuyerDiscoveryV1')
 if($null -eq $task -or $null -eq $original){Gate 'TASKS_MISSING'}
 if([int]$task.State -eq 4 -or [int]$original.State -eq 4){Gate 'TASK_STILL_RUNNING'}
 if($task.Definition.Triggers.Count -ne 0){Gate 'UNEXPECTED_TRIGGERS'}
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 if($task.Definition.Principal.UserId -ne $service){Gate 'TASK_IDENTITY_CHANGED'}
 if($task.Definition.Actions.Count -ne 1){Gate 'TASK_ACTION_COUNT_CHANGED'}
 $action=$task.Definition.Actions.Item(1)
 if($action.Path -ne $cmdexe -or $action.Arguments -ne ('/d /c "'+$bat+'"')){Gate 'TASK_ACTION_CHANGED'}
 # Validate exactly the known corrupted 14-line layout. Do not overwrite unknown file.
 $actual=[IO.File]::ReadAllLines($bat,[Text.Encoding]::ASCII)
 if($actual.Length -ne 14 -or $actual[0] -ne '@echo off' -or $actual[1] -ne 'setlocal' -or $actual[2] -ne '"' -or $actual[3] -ne $ps -or $actual[5] -ne $worker -or $actual[7] -ne $stdout -or $actual[9] -ne 'set "RC=%ERRORLEVEL%"' -or $actual[11] -ne $stdout -or $actual[13] -ne 'exit /b %RC%'){Gate 'OLD_CMD_NOT_EXPECTED_SHAPE'}
 # A task can become idle before detached interactive PowerShell exits. Never run in that case.
 $oldChild=Get-WmiObject Win32_Process -Filter 'ProcessId=23692'
 if($null -ne $oldChild -and $oldChild.Name -eq 'powershell.exe' -and $oldChild.ParentProcessId -eq 16860){Gate 'OLD_INTERACTIVE_CHILD_STILL_ALIVE'}
 $running=@(Get-WmiObject Win32_Process -Filter "Name='cmd.exe'" | Where-Object {$_.CommandLine -like '*start-diagnostic.cmd*'})
 if($running.Count -gt 0){Gate 'OLD_DIAGNOSTIC_CMD_PROCESS_STILL_ALIVE'}
 $phase='REPAIR_CMD'
 $line='"'+$ps+'" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV > "'+$stdout+'" 2>&1'
 $receipt='echo TASK_ACTION_EXIT=%RC%>>"'+$stdout+'"'
 $lines=New-Object 'System.Collections.Generic.List[string]'
 [void]$lines.Add('@echo off')
 [void]$lines.Add('setlocal')
 [void]$lines.Add($line)
 [void]$lines.Add('set "RC=%ERRORLEVEL%"')
 [void]$lines.Add($receipt)
 [void]$lines.Add('exit /b %RC%')
 [IO.File]::WriteAllLines($tmp,$lines.ToArray(),[Text.Encoding]::ASCII)
 $pre=[IO.File]::ReadAllLines($tmp,[Text.Encoding]::ASCII)
 if($pre.Length -ne 6 -or $pre[2] -ne $line -or $pre[4] -ne $receipt){Gate 'NEW_CMD_INVALID'}
 [IO.File]::Replace($tmp,$bat,$backup)
 if(-not [IO.File]::Exists($backup)){Gate 'BACKUP_MISSING'}
 $post=[IO.File]::ReadAllLines($bat,[Text.Encoding]::ASCII)
 if($post.Length -ne 6 -or $post[2] -ne $line -or $post[4] -ne $receipt){Gate 'REPLACED_CMD_INVALID'}
 'CMD_REPAIR=PASS;BACKUP=PASS;LINES=6'
 $phase='START_ONCE'
 if([int]$task.State -eq 4){Gate 'TASK_STARTED_EXTERNALLY'}
 $null=$task.Run($null)
 'DIAGNOSTIC_TASK=STARTED'
 'RESULT=STARTED;STAGE=MSP_NEWBUYER_DIAGNOSTIC_RECOVERY_V2'
 'ONEC_WRITES=0';'CRM_WRITES=0';'CUSTOMERS_DB_WRITES=0';'AUTO_UPDATE=OFF'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^RECOVERY_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_NEWBUYER_DIAGNOSTIC_RECOVERY_V2;PHASE='+$phase+';GATE='+$gate
 exit 1
}

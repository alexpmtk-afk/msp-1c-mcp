#requires -version 2
# One-time TEST SRV diagnostic task, LocalService, no 1C/CRM/SQLite customer writes.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function Fail([string]$Reason){throw ('NEWBUYER_DIAG_INSTALL_'+$Reason)}
function Digest([string]$Path){$sha=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}finally{$sha.Clear()}}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $pr=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $status=Join-Path $root 'state\msp-newbuyer-diagnostic-v1.status'
 $stdout=Join-Path $root 'state\msp-newbuyer-diagnostic-v1.stdout.txt'
 if([IO.File]::Exists($status) -or [IO.File]::Exists($stdout)){Fail 'PREVIOUS_DIAGNOSTIC_PRESENT'}
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect()
 $folder=$sched.GetFolder('\')
 $taskName='MspNewBuyerDiagnosticV1'
 $old=$folder.GetTask('MspNewBuyerDiscoveryV1')
 if($null -eq $old -or [int]$old.State -eq 4){Fail 'DISCOVERY_TASK_NOT_IDLE'}
 $existing=$null;try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){Fail 'TASK_ALREADY_EXISTS'}
 foreach($task in @($folder.GetTasks(0))){
  if($task.Name -match '^Msp(CustomerStore|Newbase|NewBase|BitrixPhone|BitrixUnnamed|BitrixName|BitrixTypeReview)' -and [int]$task.State -eq 4){Fail 'RELATED_TASK_RUNNING'}
 }
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\msp-newbuyer-diagnostic-v1'
 if([IO.Directory]::Exists($dir)){Fail 'STAGING_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'diagnose-newbuyer-execution-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/a8ce84504374ac51e4ce08e779a3e5cf42dd2ac0/integrations/msp-bitrix24-bridge/bin/diagnose-newbuyer-execution-v1.ps1'
 $exe=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $exe -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Fail 'DOWNLOAD_FAILED'}
 if((Digest $worker) -ne 'f9bc8f9ac65025b6b5d5eee6737f060e6ef00a2f72a5b4f41519d4693e16fe60'){Fail 'WORKER_HASH_MISMATCH'}
 if(([IO.File]::GetAttributes($worker) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'WORKER_REPARSE'}
 $errors=$null;$null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'WORKER_PS2_PARSE_FAILED'}
 $bat=Join-Path $dir 'start-diagnostic.cmd'
 $ps=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $lines=@('@echo off','setlocal','"'+$ps+'" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV > "'+$stdout+'" 2>&1','set "RC=%ERRORLEVEL%"','echo TASK_ACTION_EXIT=%RC%>>"'+$stdout+'"','exit /b %RC%')
 [IO.File]::WriteAllLines($bat,$lines,[Text.Encoding]::ASCII)
 'DIAGNOSTIC_WORKER_HASH=PASS'
 $phase='REGISTER'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sched.NewTask(0)
 $def.RegistrationInfo.Description='One-shot LocalService diagnostics only. Read SQLite/OData count/PowerShell task state. No customer or CRM writes.'
 $def.Principal.UserId=$service;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT5M';$def.Settings.MultipleInstances=2
 $act=$def.Actions.Create(0);$act.Path=Join-Path $env:windir 'System32\cmd.exe'
 $act.Arguments='/d /c "'+$bat+'"'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$service,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){Fail 'TRIGGERS_PRESENT'}
 $phase='START';$null=$task.Run($null)
 'DIAGNOSTIC_TASK=STARTED'
 'DIAGNOSTIC_STATUS='+$status
 'DIAGNOSTIC_STDOUT='+$stdout
 'ONEC_WRITES=0';'CRM_WRITES=0';'CUSTOMER_DB_WRITES=0'
 'RESULT=STARTED;STAGE=MSP_NEWBUYER_DIAGNOSTIC_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBUYER_DIAG_INSTALL_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_NEWBUYER_DIAGNOSTIC_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

#requires -version 2
# Manually launched one-shot SRV LocalService encrypted webhook REST read-only proof. No main task changes or CRM/1C writes.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$created=$false
$success=$false
$cleanup='NOT_REQUIRED'
$taskName='MspBitrixLocalServiceApiV2Once'
$task=$null
function Fail([string]$Code){throw ('RUN_SERVICE_API_'+$Code)}
function Hash([string]$File){
 $sha=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}finally{$sha.Clear()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $wid=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $wid
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATED_ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $probe=Join-Path $root 'staging\probe-bitrix-localservice-api-readonly-v2.ps1'
 $result=Join-Path $root 'state\bitrix-localservice-api-readonly-v2-status.txt'
 $collector=Join-Path $root 'config\collector.ini'
 $proof=Join-Path $root 'state\bitrix-direct-enrolled-webhook-api-readonly-status.txt'
 foreach($file in @($curl,$ca,$collector,$proof)){
  if(-not [IO.File]::Exists($file)){Fail 'PRECONDITION_FILE_MISSING'}
  if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
 }
 foreach($file in @($probe,$result)){
  if([IO.File]::Exists($file)){Fail 'PREVIOUS_ATTEMPT_DIAGNOSE_FIRST'}
 }
 foreach($legacy in @('config\bitrix-search-worker.ini','secrets\bitrix-search-worker.dpapi')){
  if([IO.File]::Exists((Join-Path $root $legacy))){Fail 'OLD_RELAY_CONFIG_PRESENT'}
 }
 $idle=[IO.File]::ReadAllText($collector,[Text.Encoding]::ASCII)
 foreach($g in @('ACTIVE=0','BITRIX=0')){
  if($idle -notmatch ('(?m)^'+$g+'\s*$')){Fail 'COLLECTOR_AUTOSTART_NOT_IDLE'}
 }
 # The previous failed receipt remains intact; do not relaunch or overwrite the V1 task.
 $priorFailure=Join-Path $root 'state\bitrix-localservice-api-readonly-status.txt'
 if(-not [IO.File]::Exists($priorFailure)){Fail 'PRIOR_FAILED_PROBE_RECEIPT_MISSING'}
 if([IO.File]::ReadAllText($priorFailure,[Text.Encoding]::ASCII).Trim() -cne 'STATUS=FAIL;IDENTITY=LOCAL_SERVICE;GATE=SECRET_PERMISSIONS_INVALID;PHASE=PRECHECK'){Fail 'PRIOR_FAILED_PROBE_RECEIPT_CHANGED'}
 $previous=[IO.File]::ReadAllText($proof,[Text.Encoding]::ASCII).Trim()
 if($previous -notmatch '^UTC=[^;]+;STATUS=PASS;TARGET=b24-uwmjda\.bitrix24\.ru;METHOD=crm\.requisite\.preset\.field\.list;PRESET_ID=1;FIELD_COUNT=13;RQ_INN=1;RQ_KPP=1;RQ_OGRN=1;RQ_COMPANY_NAME=1;RQ_COMPANY_FULL_NAME=1;CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=YES_ENCRYPTED$'){Fail 'ENROLLED_API_NOT_ACCEPTED'}
 $scheduler=New-Object -ComObject Schedule.Service
 $scheduler.Connect()
 $folder=$scheduler.GetFolder('\')
 $main=$folder.GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'MAIN_TASK_MISSING'}
 $account=$main.Definition.Principal.UserId
 if($account -eq 'S-1-5-19'){$sid=$account}else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $account).Translate([Security.Principal.SecurityIdentifier]).Value}
 if($sid -ne 'S-1-5-19'){Fail 'MAIN_TASK_WRONG_IDENTITY'}
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_AUTOSTART_ENABLED'}}
 $oldTask=$null
 try{$oldTask=$folder.GetTask('MspBitrixLocalServiceApiOnce')}catch{}
 if($null -ne $oldTask){Fail 'OLD_FAILED_TASK_NOT_REMOVED'}
 $existing=$null
 try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){Fail 'TEMP_TASK_ALREADY_EXISTS'}
 $phase='FETCH_PINNED_API_PROBE'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/3af7882469d668d9b14e6cb1f51c27ae22582cfd/integrations/msp-bitrix24-bridge/bin/probe-bitrix-localservice-api-readonly-v2.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --proto '=https' --tlsv1.2 --tls-max 1.2 --cacert $ca --max-redirs 0 --output $probe $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($probe)){Fail 'PROBE_DOWNLOAD_FAILED'}
 if((Hash $probe) -ne '__V2_CHILD_SHA256__'){Fail 'PROBE_HASH_MISMATCH'}
 $parse=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($probe,[Text.Encoding]::ASCII),[ref]$parse)
 if($parse -and $parse.Count -gt 0){Fail 'PS2_PARSE_FAILED'}
 'LOCAL_SERVICE_API_PROBE_SHA256=PASS'
 $phase='REGISTER_MANUAL_SERVICE_TASK'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$scheduler.NewTask(0)
 $def.RegistrationInfo.Description='One time LOCAL SERVICE Bitrix REST metadata read only; zero schedule triggers'
 $def.Principal.UserId=$service
 $def.Principal.LogonType=5
 $def.Principal.RunLevel=0
 $def.Settings.Enabled=$true
 $def.Settings.ExecutionTimeLimit='PT1M'
 $def.Settings.MultipleInstances=2
 $act=$def.Actions.Create(0)
 $act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$service,$null,5,$null)
 $created=$true
 $task=$folder.GetTask($taskName)
 if($task.Definition.Triggers.Count -ne 0){Fail 'TEMP_TASK_HAS_TRIGGERS'}
 $phase='RUN_ONCE'
 $started=[DateTime]::UtcNow
 $null=$task.Run($null)
 $phase='AWAIT_SAFE_RECEIPT'
 $accepted=$false
 for($i=0;$i -lt 100;$i++){
  Start-Sleep -Milliseconds 500
  if(-not [IO.File]::Exists($result)){continue}
  $text=$null
  try{$text=[IO.File]::ReadAllText($result,[Text.Encoding]::ASCII).Trim()}catch [IO.IOException]{continue}
  if(-not $text){continue}
  if($text -match '^STATUS=FAIL;IDENTITY=LOCAL_SERVICE;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
   'CHILD_FAILURE_GATE='+$Matches[1]
   'CHILD_FAILURE_PHASE='+$Matches[2]
   Fail 'CHILD_SERVICE_API_FAILED'
  }
  if($text -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;TARGET=b24-uwmjda\.bitrix24\.ru;METHOD=crm\.requisite\.preset\.field\.list;PRESET_ID=1;FIELD_COUNT=13;RQ_INN=1;RQ_KPP=1;RQ_OGRN=1;RQ_COMPANY_NAME=1;RQ_COMPANY_FULL_NAME=1;CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=YES_ENCRYPTED$'){
   if([DateTime]::Parse($Matches[1]).ToUniversalTime() -ge $started.AddSeconds(-3)){$accepted=$true;break}
  }
  # It may be a partially written receipt: keep waiting for a stable complete line.
 }
 if(-not $accepted){Fail 'API_RESULT_NOT_RECEIVED'}
 $phase='CLEANUP_TEMP_TASK'
 for($i=0;$i -lt 40;$i++){
  if($task.State -ne 4){break}
  Start-Sleep -Milliseconds 250
 }
 if($task.State -eq 4){Fail 'TEMP_TASK_STILL_RUNNING'}
 $folder.DeleteTask($taskName,0)
 $created=$false
 $cleanup='YES'
 $left=$null
 try{$left=$folder.GetTask($taskName)}catch{}
 if($null -ne $left){Fail 'TEMP_TASK_REMOVE_UNCONFIRMED'}
 $main=$folder.GetTask('MspCustomerStoreSync')
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_AUTOSTART_CHANGED'}}
 $success=$true
 'LOCAL_SERVICE_API_READ=PASS'
 'LOCAL_SERVICE_ENCRYPTED_WEBHOOK=PASS'
 'PRESET_ID=1'
 'FIELD_COUNT=13'
 'RQ_INN=1'
 'RQ_KPP=1'
 'RQ_OGRN=1'
 'RQ_COMPANY_NAME=1'
 'RQ_COMPANY_FULL_NAME=1'
 'WEBHOOK_SOURCE=MACHINE_DPAPI'
 'CRM_WRITES=NO'
 'ONEC_CALLS=NO'
 'CUSTOMER_DATA_EXPORTED=NO'
 'TEMP_TASK_REMOVED=YES'
 'MAIN_COLLECTOR_AUTOSTART=OFF'
 'RESULT=PASS;STAGE=SRV_BITRIX_LOCAL_SERVICE_API_READONLY_V2'
}catch{
 $exceptionType=$_.Exception.GetType().Name
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^RUN_SERVICE_API_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($created -and $null -ne $task -and $task.State -ne 4){
  try{$folder.DeleteTask($taskName,0);$created=$false;$cleanup='YES'}catch{$cleanup='FAILED'}
 }
 'TEMP_TASK_REMOVED='+$cleanup
 'RESULT=FAIL;STAGE=SRV_BITRIX_LOCAL_SERVICE_API_READONLY_V2;GATE='+$gate+';PHASE='+$phase+';EXCEPTION_TYPE='+$exceptionType
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}
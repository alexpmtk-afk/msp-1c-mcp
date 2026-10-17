#requires -version 2
# One-shot SRV JSON1 LocalService runtime acceptance; fail closed, no existing task mutations.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('JSON1_RUN_'+$Code)}
function Hash([string]$File){
 $s=New-Object System.Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$s.Clear()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $id
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $db=Join-Path $root 'data\customers.db'
 $exe=Join-Path $root 'bin\sqlite3.exe'
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $collector=Join-Path $root 'config\collector.ini'
 $bridge='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
 $old=Join-Path $root 'state\bitrix-worker-runtime-smoke-status.txt'
 $status=Join-Path $root 'state\bitrix-json1-v2-smoke-status.txt'
 $probe=Join-Path $root 'bin\probe-bitrix-json1-service-v2.ps1'
 $taskName='MspCustomerStoreBitrixJson1V2'
 foreach($f in @($curl,$ca,$exe,$db,$worker,$adapter,$collector,$bridge,$old)){
  if(-not [IO.File]::Exists($f)){Fail 'REQUIRED_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 if([IO.File]::Exists($probe) -or [IO.File]::Exists($status)){Fail 'PREVIOUS_JSON1_PROBE_REQUIRES_DIAGNOSIS'}
 if([IO.File]::ReadAllText($old,[Text.Encoding]::ASCII).Trim() -ne 'STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=CLR_JSON_CAPABILITY'){Fail 'OLD_FAILURE_RECEIPT_CHANGED'}
 if([IO.File]::Exists((Join-Path $root 'config\bitrix-search-worker.ini')) -or [IO.File]::Exists((Join-Path $root 'secrets\bitrix-search-worker.dpapi'))){Fail 'WORKER_ALREADY_ENABLED_OR_CONFIGURED'}
 if((Hash $worker) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'WORKER_HASH_CHANGED'}
 if((Hash $adapter) -ne 'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'){Fail 'ADAPTER_HASH_CHANGED'}
 foreach($item in @(@($collector,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),@($bridge,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')))){
  $raw=[IO.File]::ReadAllText([string]$item[0],[Text.Encoding]::ASCII)
  foreach($flag in $item[1]){if($raw -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_FLAG_CHANGED'}}
 }
 $scheduler=New-Object -ComObject Schedule.Service
 $scheduler.Connect()
 $folder=$scheduler.GetFolder('\')
 $main=$folder.GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'MAIN_TASK_MISSING'}
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_COLLECTOR_AUTOSTART_ENABLED'}}
 $oldTask=$null
 try{$oldTask=$folder.GetTask('MspCustomerStoreBitrixRuntimeSmoke')}catch{}
 if($null -ne $oldTask){Fail 'OLD_FAILED_TASK_STILL_PRESENT'}
 $existing=$null
 try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){Fail 'JSON1_TASK_ALREADY_EXISTS'}
 $phase='DOWNLOAD_VERIFIED_PROBE'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/cfcdb5a92bac85853d3617663f64928906286e57/integrations/msp-bitrix24-bridge/bin/probe-bitrix-json1-service-v2.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $probe $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($probe)){Fail 'PROBE_DOWNLOAD_FAILED'}
 if((Hash $probe) -ne 'a17ee3e71fc7f95cc957fbdd0835c2d4489335baf5b9928bddd6a5c330ada2fc'){Fail 'PROBE_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($probe,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'PS2_PARSE_FAILED'}
 'PROBE_SCRIPT_SHA256=PASS'
 $phase='LOCAL_SERVICE_RUNTIME'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$scheduler.NewTask(0)
 $definition.RegistrationInfo.Description='One-time read-only PS2 LocalService Bitrix JSON1 v2 capability smoke'
 $definition.Principal.UserId=$service
 $definition.Principal.LogonType=5
 $definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true
 $definition.Settings.ExecutionTimeLimit='PT3M'
 $definition.Settings.MultipleInstances=2
 $action=$definition.Actions.Create(0)
 $action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$definition,2,$service,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($task.Definition.Triggers.Count -ne 0){Fail 'AUTO_TRIGGER_UNEXPECTED'}
 $started=[DateTime]::UtcNow
 $null=$task.Run($null)
 $passed=$false
 for($i=0;$i -lt 240;$i++){
  Start-Sleep -Milliseconds 500
  if(-not [IO.File]::Exists($status)){continue}
  $line=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII).Trim()
  if($line -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
   'JSON1_FAILURE_GATE='+$Matches[1]
   'JSON1_FAILURE_PHASE='+$Matches[2]
   Fail 'LOCAL_SERVICE_PROBE_FAILED'
  }
  if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;PS2_X64=PASS;JSON1=PASS;UTF8=PASS;CUSTOMERS=6433;SEARCH_INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){
   $time=[DateTime]::Parse($Matches[1]).ToUniversalTime()
   if($time -ge $started.AddSeconds(-2)){$passed=$true;break}
  }
 }
 if(-not $passed){Fail 'RESULT_MISSING_OR_INVALID'}
 $phase='BACKREAD_AND_CLEANUP'
 $count=@(& $exe -readonly -batch -bail $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;" 2>&1)
 if($LASTEXITCODE -ne 0 -or ($count -join '').Trim() -ne '6433:6433'){Fail 'DB_CUSTOMERS_CHANGED'}
 $index=@(& $exe -readonly -batch -bail $db 'SELECT count(*) FROM customer_search_v1;' 2>&1)
 if($LASTEXITCODE -ne 0 -or ($index -join '').Trim() -ne '6433'){Fail 'DB_INDEX_CHANGED'}
 $folder.DeleteTask($taskName,0)
 $left=$null
 try{$left=$folder.GetTask($taskName)}catch{}
 if($null -ne $left){Fail 'TASK_REMOVAL_UNCONFIRMED'}
 'BITRIX_JSON1_LOCAL_SERVICE=PASS'
 'BITRIX_JSON1_CYRILLIC_ROUNDTRIP=PASS'
 'BITRIX_JSON1_INVALID_INPUT_REJECTED=YES'
 'SRV_CUSTOMER_DB_UNCHANGED=6433'
 'SRV_SEARCH_INDEX_UNCHANGED=6433'
 'JSON1_TEMP_TASK_REMOVED=YES'
 'OLD_FAILURE_RECEIPT_PRESERVED=YES'
 'MAIN_COLLECTOR_AUTOSTART=OFF'
 'WORKER_STILL_DISABLED=YES'
 'CUSTOMER_DATA_EXPORTED=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_JSON1_LOCAL_SERVICE_ACCEPTANCE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^JSON1_RUN_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_JSON1_LOCAL_SERVICE_ACCEPTANCE;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}
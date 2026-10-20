#requires -version 2
# Run a one-time read-only PS2/CLR runtime probe as LOCAL SERVICE.
# Creates a zero-trigger temporary Task Scheduler task, removes it on PASS.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('RUN_'+$Code)}
function Hash([string]$File){
 $sha=New-Object System.Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$sha.Clear()}
}
function Sql([string]$Exe,[string]$Db,[string]$Command){
 $r=@(& $Exe -readonly -batch -bail $Db $Command 2>&1)
 if($LASTEXITCODE -ne 0){Fail 'DB_READONLY_CHECK_FAILED'}
 return ($r -join '').Trim()
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $user=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $user
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $exe=Join-Path $root 'bin\sqlite3.exe'
 $db=Join-Path $root 'data\customers.db'
 $config=Join-Path $root 'config\collector.ini'
 $legacy='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $probe=Join-Path $root 'bin\probe-bitrix-worker-runtime-service.ps1'
 $status=Join-Path $root 'state\bitrix-worker-runtime-smoke-status.txt'
 $workerConfig=Join-Path $root 'config\bitrix-search-worker.ini'
 $secret=Join-Path $root 'secrets\bitrix-search-worker.dpapi'
 foreach($f in @($curl,$ca,$exe,$db,$config,$legacy,$worker,$adapter)){
  if(-not [IO.File]::Exists($f)){Fail 'MACHINE_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'MACHINE_COMPONENT_REPARSE'}
 }
 if([IO.File]::Exists($probe) -or [IO.File]::Exists($status)){Fail 'PREVIOUS_RUNTIME_PROBE_REQUIRES_DIAGNOSIS'}
 if([IO.File]::Exists($workerConfig) -or [IO.File]::Exists($secret)){Fail 'WORKER_ALREADY_CONFIGURED'}
 if((Hash $worker) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'WORKER_HASH_CHANGED'}
 if((Hash $adapter) -ne 'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'){Fail 'ADAPTER_HASH_CHANGED'}
 foreach($pair in @(@($config,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),
                     @($legacy,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')))){
  $raw=[IO.File]::ReadAllText([string]$pair[0],[Text.Encoding]::ASCII)
  foreach($flag in $pair[1]){if($raw -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_CHANGED'}}
 }
 if((Sql $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'DB_COUNT_CHANGED'}
 if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY_CHANGED'}
 $scheduler=New-Object -ComObject Schedule.Service
 $scheduler.Connect()
 $folder=$scheduler.GetFolder('\')
 $main=$folder.GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'MAIN_TASK_MISSING'}
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_COLLECTOR_AUTOSTART_ENABLED'}}
 $mainAccount=$main.Definition.Principal.UserId
 if($mainAccount -eq 'S-1-5-19'){$mainSid=$mainAccount}else{$mainSid=(New-Object Security.Principal.NTAccount -ArgumentList $mainAccount).Translate([Security.Principal.SecurityIdentifier]).Value}
 if($mainSid -ne 'S-1-5-19'){Fail 'MAIN_IDENTITY_CHANGED'}
 $old=$null
 try{$old=$folder.GetTask('MspCustomerStoreBitrixRuntimeSmoke')}catch{}
 if($null -ne $old){Fail 'ONE_TIME_TASK_ALREADY_EXISTS'}
 $phase='DOWNLOAD_VERIFIED_READONLY_PROBE'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/f6be61e3e96963c5dfe28b37139ec9a6dfb1af8f/integrations/msp-bitrix24-bridge/bin/probe-bitrix-worker-runtime-service.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $probe $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($probe)){Fail 'PROBE_DOWNLOAD_FAILED'}
 if((Hash $probe) -ne '237c57cab1d011a83f5f293d03d03ca53d3494bb1b50eb40d6babcfcee768515'){Fail 'PROBE_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($probe,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'PS2_PARSE_FAILED'}
 'PROBE_SCRIPT_SHA256=PASS'
 $phase='SERVICE_RUNTIME'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$scheduler.NewTask(0)
 $definition.RegistrationInfo.Description='One-time read-only PS2 LocalService Bitrix worker runtime smoke'
 $definition.Principal.UserId=$service
 $definition.Principal.LogonType=5
 $definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true
 $definition.Settings.ExecutionTimeLimit='PT3M'
 $definition.Settings.MultipleInstances=2
 $action=$definition.Actions.Create(0)
 $action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition('MspCustomerStoreBitrixRuntimeSmoke',$definition,2,$service,$null,5,$null)
 $task=$folder.GetTask('MspCustomerStoreBitrixRuntimeSmoke')
 if($task.Definition.Triggers.Count -ne 0){Fail 'TASK_HAS_AUTO_TRIGGER'}
 $started=[DateTime]::UtcNow
 $null=$task.Run($null)
 $ok=$false
 for($i=0;$i -lt 240;$i++){
  Start-Sleep -Milliseconds 500
  if(-not [IO.File]::Exists($status)){continue}
  $line=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII).Trim()
  if($line -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
   'RUNTIME_SMOKE_FAILURE_GATE='+$Matches[1]
   'RUNTIME_SMOKE_FAILURE_PHASE='+$Matches[2]
   Fail 'SERVICE_RUNTIME_SMOKE_FAILED'
  }
  if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;PS2_X64=PASS;CLR_JSON=PASS;UTF8=PASS;WORKER_HASH=PASS;ADAPTER_HASH=PASS;CUSTOMERS=6433;SEARCH_INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){
   $t=[DateTime]::Parse($Matches[1]).ToUniversalTime()
   if($t -ge $started.AddSeconds(-2)){$ok=$true;break}
  }
 }
 if(-not $ok){Fail 'SERVICE_SMOKE_RESULT_MISSING'}
 $phase='BACKREAD_AND_REMOVE_ONE_TIME_TASK'
 if((Sql $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'POST_SMOKE_DB_COUNT_CHANGED'}
 if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'POST_SMOKE_DB_INTEGRITY_FAILED'}
 $folder.DeleteTask('MspCustomerStoreBitrixRuntimeSmoke',0)
 $left=$null
 try{$left=$folder.GetTask('MspCustomerStoreBitrixRuntimeSmoke')}catch{}
 if($null -ne $left){Fail 'TEMP_TASK_REMOVAL_UNCONFIRMED'}
 'BITRIX_WORKER_LOCAL_SERVICE_RUNTIME=PASS'
 'BITRIX_PS2_X64_AND_CLR=PASS'
 'BITRIX_JSON_AND_UTF8_SYNTHETIC=PASS'
 'BITRIX_WORKER_STILL_DISABLED=YES'
 'SRV_CUSTOMER_DB_UNCHANGED=6433'
 'RUNTIME_TEMP_TASK_REMOVED=YES'
 'MAIN_COLLECTOR_AUTOSTART=OFF'
 'CUSTOMER_DATA_EXPORTED=NO'
 'NETWORK_PROBE_REQUESTS=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_WORKER_RUNTIME_ACCEPTANCE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^RUN_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_WORKER_RUNTIME_ACCEPTANCE;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}

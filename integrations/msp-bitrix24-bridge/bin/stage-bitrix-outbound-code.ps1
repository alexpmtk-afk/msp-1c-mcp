#requires -version 2
# Stage inactive Bitrix24 outbound worker and update local read-only query adapter.
# No service/task created; no requests to 1C, REMOTE relay or Bitrix24.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('STAGE_'+$Code)}
function Hash([string]$File){
 $s=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$s.Clear()}
}
function Query([string]$exe,[string]$db,[string]$sql){
 $result=@(& $exe -readonly -batch -bail $db $sql 2>&1)
 if($LASTEXITCODE -ne 0){Fail 'SQLITE_READ_FAILED'}
 return ($result -join '').Trim()
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
 $sql=Join-Path $root 'bin\sqlite3.exe'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $newAdapter=Join-Path $root 'staging\query-bitrix-search-index-v2-verified.ps1'
 $newWorker=Join-Path $root 'staging\bitrix-search-outbound-once-verified.ps1'
 $backup=Join-Path $root 'staging\query-bitrix-search-index-before-stdin.ps1'
 $receipt=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 $config=Join-Path $root 'config\collector.ini'
 $bridge='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
 $workerConfig=Join-Path $root 'config\bitrix-search-worker.ini'
 $workerSecret=Join-Path $root 'secrets\bitrix-search-worker.dpapi'
 foreach($f in @($curl,$ca,$db,$sql,$adapter,$receipt,$config,$bridge)){
  if(-not [IO.File]::Exists($f)){Fail 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 foreach($f in @($worker,$newAdapter,$newWorker,$backup,$workerConfig,$workerSecret)){
  if([IO.File]::Exists($f)){Fail 'PREVIOUS_STAGE_OR_WORKER_CONFIGURATION'}
 }
 if((Hash $adapter) -ne '1c3cf6832bf513a9b5b4f1ac4907bfa85b9b8119f7b91b005e64df4f05fe02f8'){Fail 'OLD_ADAPTER_SHA256_CHANGED'}
 foreach($item in @(@($config,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),
                   @($bridge,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')))){
  $raw=[IO.File]::ReadAllText([string]$item[0],[Text.Encoding]::ASCII)
  foreach($flag in $item[1]){if($raw -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'EXISTING_TASK_NOT_SAFE_IDLE'}}
 }
 $s=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 if($s -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INDEX_RECEIPT_NOT_ACCEPTED'}
 if((Query $sql $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'CUSTOMERS_CHANGED'}
 if((Query $sql $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY_FAILED'}
 $scheduler=New-Object -ComObject Schedule.Service
 $scheduler.Connect()
 $main=$scheduler.GetFolder('\').GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'COLLECTOR_TASK_MISSING'}
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'COLLECTOR_AUTOSTART_ENABLED'}}
 $phase='STAGE_PINNED_ARTIFACTS'
 $base='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/45e1f072ad1eeb1f39fc115f37ed6d16ae5d8b71/integrations/msp-bitrix24-bridge/bin/'
 foreach($spec in @(
  @('query-bitrix-search-index.ps1',$newAdapter,'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'),
  @('bitrix-search-outbound-once.ps1',$newWorker,'8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff')
 )){
  & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $spec[1] ($base+$spec[0])
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($spec[1])){Fail 'DOWNLOAD_FAILED'}
  if((Hash $spec[1]) -ne $spec[2]){Fail 'PINNED_SHA256_FAILED'}
  $errors=$null
  $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($spec[1],[Text.Encoding]::ASCII),[ref]$errors)
  if($errors -and $errors.Count -gt 0){Fail 'PS2_PARSE_FAILED'}
 }
 'DOWNLOADED_SCRIPTS_SHA256=PASS'
 $phase='ATOMIC_STAGING'
 [IO.File]::Move($newWorker,$worker)
 [IO.File]::Replace($newAdapter,$adapter,$backup)
 if((Hash $worker) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'WORKER_STAGED_HASH_MISMATCH'}
 if((Hash $adapter) -ne 'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'){Fail 'ADAPTER_STAGED_HASH_MISMATCH'}
 if((Hash $backup) -ne '1c3cf6832bf513a9b5b4f1ac4907bfa85b9b8119f7b91b005e64df4f05fe02f8'){Fail 'BACKUP_HASH_MISMATCH'}
 if((Query $sql $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'DB_CHANGED_AFTER_STAGING'}
 if((Query $sql $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY_AFTER_STAGING'}
 'SEARCH_ADAPTER_STAGED=PASS'
 'OUTBOUND_WORKER_STAGED=PASS'
 'ORIGINAL_ADAPTER_BACKUP=PASS'
 'WORKER_CONFIGURATION_CREATED=NO'
 'WORKER_TOKEN_CREATED=NO'
 'WORKER_TASK_REGISTERED=NO'
 'OUTBOUND_NETWORK_REQUESTS=NO'
 'MAIN_COLLECTOR_AUTOSTART=OFF'
 'CUSTOMER_DATA_EXPORTED=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_OUTBOUND_CODE_STAGING'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^STAGE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_OUTBOUND_CODE_STAGING;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}

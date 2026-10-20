#requires -version 2
# Inactive, atomic JSON1 worker replacement on physical SRV. Never starts a task.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('JSON1_STAGE_'+$Code)}
function Hash([string]$File){
 $s=New-Object System.Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$s.Clear()}
}
function ReadSql([string]$Exe,[string]$Db,[string]$Statement){
 $o=@(& $Exe -readonly -batch -bail $Db $Statement 2>&1)
 if($LASTEXITCODE -ne 0){Fail 'SQLITE_READ_FAILED'}
 return ($o -join '').Trim()
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 $db=Join-Path $root 'data\customers.db'
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $download=Join-Path $root 'staging\bitrix-search-outbound-json1-v2-verified.ps1'
 $backup=Join-Path $root 'staging\bitrix-search-outbound-before-json1.ps1'
 $receipt=Join-Path $root 'state\bitrix-worker-json1-stage-accepted.txt'
 $indexReceipt=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 $jsonReceipt=Join-Path $root 'state\bitrix-json1-v2-smoke-status.txt'
 $oldReceipt=Join-Path $root 'state\bitrix-worker-runtime-smoke-status.txt'
 $collector=Join-Path $root 'config\collector.ini'
 $bridge='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
 $newIni=Join-Path $root 'config\bitrix-search-worker.ini'
 $newSecret=Join-Path $root 'secrets\bitrix-search-worker.dpapi'
 foreach($f in @($curl,$ca,$sqlite,$db,$worker,$adapter,$indexReceipt,$jsonReceipt,$oldReceipt,$collector,$bridge)){
  if(-not [IO.File]::Exists($f)){Fail 'REQUIRED_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 foreach($f in @($download,$backup,$receipt,$newIni,$newSecret)){
  if([IO.File]::Exists($f)){Fail 'PRIOR_UPGRADE_OR_WORKER_CONFIGURATION'}
 }
 if((Hash $worker) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'OLD_WORKER_HASH_CHANGED'}
 if((Hash $adapter) -ne 'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'){Fail 'ADAPTER_HASH_CHANGED'}
 if([IO.File]::ReadAllText($oldReceipt,[Text.Encoding]::ASCII).Trim() -ne 'STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=CLR_JSON_CAPABILITY'){Fail 'OLD_FAILURE_RECEIPT_CHANGED'}
 $jr=[IO.File]::ReadAllText($jsonReceipt,[Text.Encoding]::ASCII).Trim()
 if($jr -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;PS2_X64=PASS;JSON1=PASS;UTF8=PASS;CUSTOMERS=6433;SEARCH_INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'JSON1_RUNTIME_NOT_ACCEPTED'}
 $ir=[IO.File]::ReadAllText($indexReceipt,[Text.Encoding]::ASCII).Trim()
 if($ir -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INDEX_RECEIPT_CHANGED'}
 foreach($item in @(@($collector,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),@($bridge,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')))){
  $raw=[IO.File]::ReadAllText([string]$item[0],[Text.Encoding]::ASCII)
  foreach($flag in $item[1]){if($raw -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_CHANGED'}}
 }
 $scheduler=New-Object -ComObject Schedule.Service
 $scheduler.Connect()
 $folder=$scheduler.GetFolder('\')
 $main=$folder.GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'COLLECTOR_TASK_MISSING'}
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'COLLECTOR_AUTOSTART_ENABLED'}}
 foreach($task in $folder.GetTasks(1)){
  foreach($action in $task.Definition.Actions){
   if($action.Type -eq 0 -and $action.Arguments -match 'bitrix-search-outbound-once\.ps1'){Fail 'WORKER_SCHEDULED_ALREADY'}
  }
 }
 foreach($taskName in @('MspCustomerStoreBitrixRuntimeSmoke','MspCustomerStoreBitrixJson1V2')){
  $found=$null
  try{$found=$folder.GetTask($taskName)}catch{}
  if($null -ne $found){Fail 'TEMP_RUNTIME_TASK_NOT_REMOVED'}
 }
 if((ReadSql $sqlite $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'CUSTOMERS_CHANGED'}
 if((ReadSql $sqlite $db 'SELECT count(*) FROM customer_search_v1;') -ne '6433'){Fail 'SEARCH_INDEX_CHANGED'}
 if((ReadSql $sqlite $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY_FAILED'}
 $phase='DOWNLOAD_PINNED_WORKER'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/b896b148078a6c4aa7d5dc002ead6aa037d74670/integrations/msp-bitrix24-bridge/bin/bitrix-search-outbound-once.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $download $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($download)){Fail 'WORKER_DOWNLOAD_FAILED'}
 if((Hash $download) -ne '53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4'){Fail 'PINNED_WORKER_SHA256_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($download,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'PS2_PARSE_FAILED'}
 $body=[IO.File]::ReadAllText($download,[Text.Encoding]::ASCII)
 if($body -match 'System\.Web\.Extensions|JavaScriptSerializer' -or $body -notmatch 'function JsonSql\(' -or $body -notmatch 'json_valid\(doc\)'){Fail 'NEW_WORKER_CONTRACT_INVALID'}
 'NEW_WORKER_SHA256=PASS'
 'NEW_WORKER_PS2_PARSE=PASS'
 $phase='ATOMIC_REPLACE_DISABLED_WORKER'
 [IO.File]::Replace($download,$worker,$backup)
 if((Hash $worker) -ne '53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4'){Fail 'INSTALLED_WORKER_HASH_MISMATCH'}
 if((Hash $backup) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'ROLLBACK_COPY_HASH_MISMATCH'}
 if((Hash $adapter) -ne 'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'){Fail 'ADAPTER_MODIFIED'}
 if([IO.File]::Exists($newIni) -or [IO.File]::Exists($newSecret)){Fail 'WORKER_CONFIGURATION_CREATED'}
 if((ReadSql $sqlite $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'POST_STAGE_CUSTOMERS_CHANGED'}
 if((ReadSql $sqlite $db 'SELECT count(*) FROM customer_search_v1;') -ne '6433'){Fail 'POST_STAGE_INDEX_CHANGED'}
 if((ReadSql $sqlite $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'POST_STAGE_INTEGRITY_FAILED'}
 $phase='WRITE_RECEIPT'
 $mark='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;STAGE=BITRIX_JSON1_WORKER_INACTIVE_UPGRADE;OLD_HASH=8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff;NEW_HASH=53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4;CUSTOMERS=6433;INDEX=6433;NETWORK_WORKER_ENABLED=NO'
 $stream=New-Object IO.FileStream -ArgumentList @($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$b=[Text.Encoding]::ASCII.GetBytes($mark);$stream.Write($b,0,$b.Length);$stream.Flush()}finally{$stream.Close()}
 'WORKER_JSON1_CODE_INSTALLED=PASS'
 'ROLLBACK_COPY_PRESERVED=PASS'
 'SEARCH_ADAPTER_UNCHANGED=PASS'
 'CUSTOMER_DB_UNCHANGED=6433'
 'SEARCH_INDEX_UNCHANGED=6433'
 'WORKER_TOKEN_CREATED=NO'
 'WORKER_CONFIGURATION_CREATED=NO'
 'WORKER_TASK_CREATED=NO'
 'MAIN_COLLECTOR_AUTOSTART=OFF'
 'CUSTOMER_DATA_EXPORTED=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_JSON1_WORKER_INACTIVE_UPGRADE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^JSON1_STAGE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_JSON1_WORKER_INACTIVE_UPGRADE;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}
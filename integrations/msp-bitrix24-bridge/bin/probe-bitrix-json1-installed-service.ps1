#requires -version 2
# LocalService READ-ONLY acceptance of installed Bitrix JSON1 worker. Never invoke it.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\bitrix-json1-installed-runtime-status.txt'
function Fail([string]$Code){throw ('INSTALLED_'+$Code)}
function Hash([string]$Path){
 $h=New-Object System.Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
function Sql([string]$Db,[string]$Statement){
 $exe=Join-Path $script:root 'bin\sqlite3.exe'
 $r=@(& $exe -readonly -batch -bail $Db $Statement 2>&1)
 if($LASTEXITCODE -ne 0){Fail 'SQLITE_READ_FAILED'}
 return ($r -join '').Trim()
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 if([IO.File]::Exists($status)){Fail 'ALREADY_TESTED'}
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $backup=Join-Path $root 'staging\bitrix-search-outbound-before-json1.ps1'
 $stage=Join-Path $root 'state\bitrix-worker-json1-stage-accepted.txt'
 $json=Join-Path $root 'state\bitrix-json1-v2-smoke-status.txt'
 $old=Join-Path $root 'state\bitrix-worker-runtime-smoke-status.txt'
 $db=Join-Path $root 'data\customers.db'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 $index=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 $ini=Join-Path $root 'config\bitrix-search-worker.ini'
 $secret=Join-Path $root 'secrets\bitrix-search-worker.dpapi'
 foreach($file in @($worker,$adapter,$backup,$stage,$json,$old,$db,$sqlite,$index)){
  if(-not [IO.File]::Exists($file)){Fail 'REQUIRED_FILE_MISSING'}
  if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
 }
 if([IO.File]::Exists($ini) -or [IO.File]::Exists($secret)){Fail 'WORKER_CONFIG_PRESENT'}
 $phase='HASHES_AND_PS2'
 if((Hash $worker) -ne '53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4'){Fail 'JSON1_WORKER_HASH'}
 if((Hash $backup) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'ROLLBACK_HASH'}
 if((Hash $adapter) -ne 'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'){Fail 'ADAPTER_HASH'}
 foreach($file in @($worker,$adapter)){
  $errors=$null
  $source=[IO.File]::ReadAllText($file,[Text.Encoding]::ASCII)
  $null=[Management.Automation.PSParser]::Tokenize($source,[ref]$errors)
  if($errors -and $errors.Count -gt 0){Fail 'PS2_PARSE_FAILED'}
 }
 $body=[IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII)
 if($body -match 'System\.Web\.Extensions|JavaScriptSerializer' -or $body -notmatch 'function JsonSql\('){Fail 'WORKER_JSON1_CONTRACT'}
 $expected=';STATUS=PASS;STAGE=BITRIX_JSON1_WORKER_INACTIVE_UPGRADE;OLD_HASH=8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff;NEW_HASH=53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4;CUSTOMERS=6433;INDEX=6433;NETWORK_WORKER_ENABLED=NO'
 if(-not [IO.File]::ReadAllText($stage,[Text.Encoding]::ASCII).Trim().EndsWith($expected)){Fail 'UPGRADE_RECEIPT_INVALID'}
 if([IO.File]::ReadAllText($old,[Text.Encoding]::ASCII).Trim() -ne 'STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=CLR_JSON_CAPABILITY'){Fail 'OLD_RECEIPT_CHANGED'}
 $jr=[IO.File]::ReadAllText($json,[Text.Encoding]::ASCII).Trim()
 if($jr -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;PS2_X64=PASS;JSON1=PASS;UTF8=PASS;CUSTOMERS=6433;SEARCH_INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'JSON1_RECEIPT_CHANGED'}
 $ir=[IO.File]::ReadAllText($index,[Text.Encoding]::ASCII).Trim()
 if($ir -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INDEX_RECEIPT_CHANGED'}
 $phase='DB_READONLY'
 if((Sql $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'CUSTOMERS_CHANGED'}
 if((Sql $db 'SELECT count(*) FROM customer_search_v1;') -ne '6433'){Fail 'INDEX_CHANGED'}
 if((Sql $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY_FAILED'}
 $phase='WRITE_RESULT'
 $line='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;IDENTITY=LOCAL_SERVICE;INSTALLED_WORKER_SHA256=PASS;ROLLBACK_SHA256=PASS;ADAPTER_SHA256=PASS;PS2_PARSE=PASS;JSON1_CONTRACT=PASS;CUSTOMERS=6433;INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0'
 $f=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$b=[Text.Encoding]::ASCII.GetBytes($line);$f.Write($b,0,$b.Length);$f.Flush()}finally{$f.Close()}
 'INSTALLED_JSON1_WORKER_LOCAL_SERVICE=PASS'
 'INSTALLED_WORKER_SHA256=PASS'
 'ROLLBACK_SHA256=PASS'
 'PS2_PARSE=PASS'
 'CUSTOMERS=6433'
 'SEARCH_INDEX=6433'
 'WORKER_ENABLED=NO'
 'NETWORK_CALLS=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=BITRIX_JSON1_INSTALLED_LOCAL_SERVICE_PROBE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^INSTALLED_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=BITRIX_JSON1_INSTALLED_LOCAL_SERVICE_PROBE;GATE='+$gate+';PHASE='+$phase
 exit 1
}
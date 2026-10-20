#requires -version 2
# Bitrix24 outbound worker: LOCAL SERVICE runtime-only smoke, no network or customer export.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\bitrix-worker-runtime-smoke-status.txt'
function Fail([string]$Code){throw ('RUNTIME_'+$Code)}
function Sha([string]$Path){
 $sha=New-Object System.Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
 finally{$sha.Clear()}
}
function Sql([string]$Exe,[string]$Db,[string]$Statement){
 $output=@(& $Exe -readonly -batch -bail $Db $Statement 2>&1)
 if($LASTEXITCODE -ne 0){Fail 'SQLITE_READONLY_FAILED'}
 return ($output -join '').Trim()
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 $db=Join-Path $root 'data\customers.db'
 $indexReceipt=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 $ini=Join-Path $root 'config\bitrix-search-worker.ini'
 $secret=Join-Path $root 'secrets\bitrix-search-worker.dpapi'
 foreach($f in @($worker,$adapter,$sqlite,$db,$indexReceipt)){
  if(-not [IO.File]::Exists($f)){Fail 'STAGED_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'STAGED_COMPONENT_REPARSE'}
 }
 if([IO.File]::Exists($status)){Fail 'SMOKE_ALREADY_EXECUTED'}
 if([IO.File]::Exists($ini) -or [IO.File]::Exists($secret)){Fail 'WORKER_ALREADY_CONFIGURED'}
 if((Sha $worker) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'WORKER_HASH_MISMATCH'}
 if((Sha $adapter) -ne 'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'){Fail 'ADAPTER_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'WORKER_PS2_PARSE'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($adapter,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'ADAPTER_PS2_PARSE'}
 $phase='CLR_JSON_CAPABILITY'
 Add-Type -AssemblyName System.Security
 Add-Type -AssemblyName System.Web.Extensions
 $serializer=New-Object System.Web.Script.Serialization.JavaScriptSerializer
 $serializer.MaxJsonLength=131072
 $personName=[regex]::Unescape('\u0422\u0435\u0441\u0442')
 $src=@{id='12345678-abcd-abcd-abcd-123456789abc';items=@(@{id='87654321-abcd-abcd-abcd-123456789abc';name=$personName})}
 $json=$serializer.Serialize($src)
 $back=$serializer.DeserializeObject($json)
 if(-not ($back -is [System.Collections.IDictionary])){Fail 'JSON_ROOT_NOT_DICTIONARY'}
 if([string]$back['id'] -ne '12345678-abcd-abcd-abcd-123456789abc'){Fail 'JSON_ID_CHANGED'}
 $items=$back['items']
 if(-not ($items -is [System.Array]) -or $items.Length -ne 1){Fail 'JSON_ITEMS_INVALID'}
 if([string]$items[0]['name'] -ne $personName){Fail 'JSON_UNICODE_ROUNDTRIP'}
 $hex=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($personName)).Replace('-','')
 if($hex -ne 'D0A2D0B5D181D182'){Fail 'UTF8_HEX_ROUNDTRIP'}
 $phase='DB_READONLY'
 $receipt=[IO.File]::ReadAllText($indexReceipt,[Text.Encoding]::ASCII).Trim()
 if($receipt -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INDEX_RECEIPT_NOT_ACCEPTED'}
 if((Sql $sqlite $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'CUSTOMERS_CHANGED'}
 if((Sql $sqlite $db 'SELECT count(*) FROM customer_search_v1;') -ne '6433'){Fail 'INDEX_COUNT_CHANGED'}
 if((Sql $sqlite $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY'}
 $phase='WRITE_RESULT'
 $msg='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+
 ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;PS2_X64=PASS;CLR_JSON=PASS;UTF8=PASS;WORKER_HASH=PASS;ADAPTER_HASH=PASS;CUSTOMERS=6433;SEARCH_INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0'
 $f=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$b=[Text.Encoding]::ASCII.GetBytes($msg);$f.Write($b,0,$b.Length);$f.Flush()}finally{$f.Close()}
 'S4_LOCAL_SERVICE=PASS'
 'S4_PS2_X64=PASS'
 'S4_CLR_JSON=PASS'
 'S4_UTF8_SYNTHETIC=PASS'
 'S4_WORKER_AND_ADAPTER_HASHES=PASS'
 'S4_SQLITE_CUSTOMERS=6433'
 'S4_SQLITE_INDEX=6433'
 'S4_SQLITE_QUICK_CHECK=ok'
 'S4_WORKER_ENABLED=NO'
 'NETWORK_CALLS=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_WORKER_RUNTIME_SMOKE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^RUNTIME_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=SRV_BITRIX_WORKER_RUNTIME_SMOKE;GATE='+$gate+';PHASE='+$phase
 exit 1
}

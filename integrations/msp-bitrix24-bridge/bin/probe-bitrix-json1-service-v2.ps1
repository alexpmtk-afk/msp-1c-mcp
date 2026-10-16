#requires -version 2
# JSON1 capability smoke for SRV LocalService; no network, customer exports, or writes to 1C.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\bitrix-json1-v2-smoke-status.txt'
function Fail([string]$Code){throw ('JSON1_'+$Code)}
function Hash([string]$File){
 $s=New-Object System.Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$s.Clear()}
}
function ExecSql([string]$Database,[string]$Sql){
 $exe=Join-Path $script:root 'bin\sqlite3.exe'
 $p=New-Object Diagnostics.Process
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=$exe
 if($Database -eq ':memory:'){$i.Arguments='-batch -bail ":memory:"'}
 else{$i.Arguments='-readonly -batch -bail "'+$Database+'"'}
 $i.UseShellExecute=$false
 $i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'SQLITE_START_FAILED'}
  $p.StandardInput.WriteLine($Sql)
  $p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(10000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $out.Length -gt 4096){Fail 'SQLITE_QUERY_FAILED'}
  return $out
 }finally{$p.Close()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 if([IO.File]::Exists($status)){Fail 'SMOKE_ALREADY_EXECUTED'}
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 $db=Join-Path $root 'data\customers.db'
 $indexReceipt=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 $oldReceipt=Join-Path $root 'state\bitrix-worker-runtime-smoke-status.txt'
 $workerIni=Join-Path $root 'config\bitrix-search-worker.ini'
 $workerSecret=Join-Path $root 'secrets\bitrix-search-worker.dpapi'
 foreach($f in @($worker,$adapter,$sqlite,$db,$indexReceipt,$oldReceipt)){
  if(-not [IO.File]::Exists($f)){Fail 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 if([IO.File]::Exists($workerIni) -or [IO.File]::Exists($workerSecret)){Fail 'WORKER_ENABLED_OR_CONFIGURED'}
 if([IO.File]::ReadAllText($oldReceipt,[Text.Encoding]::ASCII).Trim() -ne 'STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=CLR_JSON_CAPABILITY'){Fail 'ORIGINAL_FAILURE_RECEIPT_CHANGED'}
 if((Hash $worker) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'OLD_WORKER_HASH_CHANGED'}
 if((Hash $adapter) -ne 'bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b'){Fail 'ADAPTER_HASH_CHANGED'}
 $phase='JSON1_SYNTHETIC'
 $name=[regex]::Unescape('\u0422\u0435\u0441\u0442')
 $hexName=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($name)).Replace('-','')
 if($hexName -ne 'D0A2D0B5D181D182'){Fail 'CLR_UTF8_UNEXPECTED'}
 $json='{"id":"00000000-0000-0000-0000-000000000001","name":"\u0422\u0435\u0441\u0442","items":[{"name":"\u0422\u0435\u0441\u0442"}]}'
 $hex=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($json)).Replace('-','')
 $stmt="WITH j(doc) AS (SELECT CAST(X'"+$hex+"' AS TEXT)) SELECT json_valid(doc)||'|'||json_type(doc)||'|'||json_array_length(doc,'$.items')||'|'||hex(CAST(json_extract(doc,'$.name') AS BLOB)) FROM j;"
 $value=ExecSql ':memory:' $stmt
 if($value -ne ('1|object|1|'+$hexName)){Fail 'JSON1_PARSE_UTF8'}
 $jsonBad='invalid JSON'
 $hexBad=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($jsonBad)).Replace('-','')
 $bad="WITH j(doc) AS (SELECT CAST(X'"+$hexBad+"' AS TEXT)) SELECT CASE WHEN json_valid(doc)=0 THEN 'INVALID' ELSE 'VALID' END FROM j;"
 if((ExecSql ':memory:' $bad) -ne 'INVALID'){Fail 'JSON1_INVALID_INPUT_ACCEPTED'}
 $serial="SELECT hex(CAST(json_object('id','synthetic','items',json_array(json_object('name',char(0x422,0x435,0x441,0x442)))) AS BLOB));"
 $encoded=ExecSql ':memory:' $serial
 if($encoded -notmatch '^[0-9A-F]+$' -or ($encoded.Length % 2) -ne 0){Fail 'JSON1_SERIAL_INVALID'}
 $bytes=New-Object byte[] ($encoded.Length/2)
 for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=[Convert]::ToByte($encoded.Substring($i*2,2),16)}
 $back=[Text.Encoding]::UTF8.GetString($bytes)
 if($back -notmatch '"id":"synthetic"' -or $back -notmatch [regex]::Escape($name)){Fail 'JSON1_SERIAL_UTF8_FAILED'}
 $phase='DB_READONLY'
 $receipt=[IO.File]::ReadAllText($indexReceipt,[Text.Encoding]::ASCII).Trim()
 if($receipt -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INDEX_RECEIPT_CHANGED'}
 if((ExecSql $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'CUSTOMER_COUNT_CHANGED'}
 if((ExecSql $db "SELECT count(*) FROM customer_search_v1;") -ne '6433'){Fail 'SEARCH_INDEX_CHANGED'}
 if((ExecSql $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_QUICK_CHECK'}
 $phase='WRITE_RESULT'
 $msg='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;IDENTITY=LOCAL_SERVICE;PS2_X64=PASS;JSON1=PASS;UTF8=PASS;CUSTOMERS=6433;SEARCH_INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0'
 $stream=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$b=[Text.Encoding]::ASCII.GetBytes($msg);$stream.Write($b,0,$b.Length);$stream.Flush()}finally{$stream.Close()}
 'JSON1_LOCAL_SERVICE_RUNTIME=PASS'
 'JSON1_SYNTHETIC_PARSE_AND_SERIALIZE=PASS'
 'JSON1_UTF8_CYRILLIC=PASS'
 'JSON1_INVALID_INPUT_REJECTED=YES'
 'SRV_CUSTOMERS_AND_INDEX=6433'
 'DB_INTEGRITY=ok'
 'WORKER_ENABLED=NO'
 'NETWORK_CALLS=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_JSON1_SERVICE_PROBE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^JSON1_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=SRV_BITRIX_JSON1_SERVICE_PROBE;GATE='+$gate+';PHASE='+$phase
 exit 1
}
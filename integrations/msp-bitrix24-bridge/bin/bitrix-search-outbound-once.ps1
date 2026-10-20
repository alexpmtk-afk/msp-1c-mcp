#requires -version 2
# PREPARED ONLY; do not schedule until HTTPS reverse proxy and Bitrix app acceptance.
# LOCAL SERVICE outbound one-shot poll; only 20 matched clients may leave SRV.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$encrypted=$null
$plain=$null
function Fail([string]$Code){throw ('WORKER_'+$Code)}
function Quote([string]$Value){
 if($Value -match '[\x00-\x1f\x7f]'){Fail 'CONFIG_CONTROL'}
 return ('"'+$Value.Replace('\','\\').Replace('"','\"')+'"')
}
function Http([string]$Method,[string]$Route,[string]$Body){
 if(($Method -ne 'GET' -and $Method -ne 'POST') -or ($Route -ne '/worker/next' -and $Route -ne '/worker/result')){Fail 'HTTP_METHOD_ROUTE'}
 $cfg='url = '+(Quote ($script:base+$Route))+[Environment]::NewLine
 $cfg+='header = '+(Quote ('X-Msp-Worker-Token: '+$script:token))+[Environment]::NewLine
 if($Method -eq 'POST'){
  if($null -eq $Body -or $Body.Length -gt 16384 -or $Body -match '[^\x20-\x7e]'){Fail 'POST_BODY_INVALID'}
  $cfg+='header = "Content-Type: application/json"'+[Environment]::NewLine
  $cfg+='request = "POST"'+[Environment]::NewLine
  $cfg+='data-binary = '+(Quote $Body)+[Environment]::NewLine
 }else{$cfg+='request = "GET"'+[Environment]::NewLine}
 $p=New-Object Diagnostics.Process
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=$script:curl
 $i.Arguments='-q --silent --show-error --fail --noproxy "*" --proto "=https" --tlsv1.2 --tls-max 1.2 --max-redirs 0 --max-time 20 --cacert "'+$script:ca+'" --write-out "__MSP_HTTP__:%{http_code}" --config -'
 $i.UseShellExecute=$false
 $i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'CURL_START'}
  $p.StandardInput.Write($cfg)
  $p.StandardInput.Close()
  $o=$p.StandardOutput.ReadToEnd()
  $e=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'CURL_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $o.Length -gt 131072){Fail 'CURL_REQUEST_FAILED'}
  $n=$o.LastIndexOf('__MSP_HTTP__:')
  if($n -lt 0 -or $o.Substring($n+13) -notmatch '^[0-9]{3}$'){Fail 'CURL_HTTP_STATUS_INVALID'}
  return @{Code=[int]::Parse($o.Substring($n+13));Body=$o.Substring(0,$n)}
 }finally{$p.Close()}
}
# SQLite 3.43.2 JSON1 is the parser (compatible with PowerShell 2 and CLR 2.0).
# Untrusted JSON enters SQL only as UTF8 hex, supplied through process stdin.
function JsonSql([string]$Json,[string]$Select){
 if($Json.Length -gt 131072){Fail 'JSON_SIZE_EXCEEDED'}
 $hex=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($Json)).Replace('-','')
 $sql="WITH j(doc) AS (SELECT CAST(X'"+$hex+"' AS TEXT)) "+$Select
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $script:root 'bin\sqlite3.exe'
 $i.Arguments='-batch -bail ":memory:"'
 $i.UseShellExecute=$false
 $i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'JSON_SQLITE_START'}
  $p.StandardInput.WriteLine($sql)
  $p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(10000)){$p.Kill();Fail 'JSON_SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $out.Length -gt 131072){Fail 'JSON_SQLITE_FAILED'}
  return $out
 }finally{$p.Close()}
}
function DecodeHex([string]$Hex){
 if($Hex.Length -gt 131072 -or ($Hex.Length % 2) -ne 0 -or $Hex -notmatch '^[a-fA-F0-9]*$'){Fail 'JSON_HEX_INVALID'}
 $b=New-Object byte[] ($Hex.Length/2)
 for($i=0;$i -lt $b.Length;$i++){$b[$i]=[Convert]::ToByte($Hex.Substring($i*2,2),16)}
 return [Text.Encoding]::UTF8.GetString($b)
}

function ToAsciiJson([string]$Json){
 $b=New-Object Text.StringBuilder
 foreach($ch in $Json.ToCharArray()){
  $code=[int]$ch
  if($code -gt 126){[void]$b.Append('\u'+$code.ToString('x4'))}
  else{[void]$b.Append($ch)}
 }
 return $b.ToString()
}
function Search([string]$Term,[string]$Kind,[int]$Limit){
 $hex=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($Term)).Replace('-','')
 if($hex.Length -gt 640){Fail 'QUERY_BYTES_EXCESSIVE'}
 $p=New-Object Diagnostics.Process
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $PSHOME 'powershell.exe'
 $file=Join-Path $script:root 'bin\query-bitrix-search-index.ps1'
 $i.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$file+'" -ExpectedComputerName SRV -EntityType '+$Kind+' -Limit '+$Limit+' -ReadHexQueryFromStandardInput -OutputUtf8Hex'
 $i.UseShellExecute=$false
 $i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'LOCAL_QUERY_START'}
  $p.StandardInput.WriteLine($hex)
  $p.StandardInput.Close()
  $output=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(20000)){$p.Kill();Fail 'LOCAL_QUERY_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $output.Length -lt 4 -or $output.Length -gt 131072 -or ($output.Length % 2) -ne 0 -or $output -notmatch '^[a-fA-F0-9]+$'){Fail 'LOCAL_QUERY_FAILED'}
  $bytes=New-Object byte[] ($output.Length/2)
  for($j=0;$j -lt $bytes.Length;$j++){$bytes[$j]=[Convert]::ToByte($output.Substring(2*$j,2),16)}
  return [Text.Encoding]::UTF8.GetString($bytes)
 }finally{$p.Close()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 $script:root=$root
 $script:curl=Join-Path $root 'bin\curl.exe'
 $script:ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $ini=Join-Path $root 'config\bitrix-search-worker.ini'
 $secret=Join-Path $root 'secrets\bitrix-search-worker.dpapi'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $receipt=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 foreach($f in @($script:curl,$script:ca,$ini,$secret,$adapter,$receipt)){
  if(-not [IO.File]::Exists($f)){Fail 'MACHINE_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'MACHINE_COMPONENT_REPARSE'}
 }
 $cfg=@{}
 foreach($line in [IO.File]::ReadAllLines($ini,[Text.Encoding]::ASCII)){
  if($line -notmatch '^([A-Z_]+)=(.*)$'){Fail 'WORKER_CONFIG_SYNTAX'}
  if($cfg.ContainsKey($Matches[1])){Fail 'WORKER_CONFIG_DUPLICATE'}
  $cfg[$Matches[1]]=$Matches[2]
 }
 if($cfg.Count -ne 2 -or $cfg['ACTIVE'] -ne '1'){Fail 'WORKER_NOT_ENABLED'}
 $script:base=$cfg['BASE_URL']
 if($script:base -notmatch '^https://vm-817589\.tail76ae70\.ts\.net:[0-9]{2,5}/b24-relay$'){Fail 'WORKER_ENDPOINT_NOT_APPROVED'}
 $r=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII)
 if($r -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'SEARCH_INDEX_NOT_ACCEPTED'}
 $phase='DECRYPT'
 Add-Type -AssemblyName System.Security
 # JSON1 is present in sqlite3.exe, no CLR 3.5 dependency.
 $encrypted=[IO.File]::ReadAllBytes($secret)
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspBitrixSearchWorker-v1')
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 $script:token=[Text.Encoding]::Unicode.GetString($plain)
 [Array]::Clear($plain,0,$plain.Length)
 $plain=$null
 if($script:token -notmatch '^[A-Za-z0-9_-]{32,128}$'){Fail 'WORKER_TOKEN_INVALID'}
 $phase='FETCH_JOB'
 $jobReply=Http 'GET' '/worker/next' $null
 if($jobReply.Code -eq 204){
  'SEARCH_JOB=NONE'
  'CUSTOMER_DATA_EXPORTED=NO'
  'ONEC_CALLS=NO'
  'BITRIX_WRITES=NO'
  'RESULT=PASS;STAGE=SRV_BITRIX_SINGLE_OUTBOUND_POLL'
  exit 0
 }
 if($jobReply.Code -ne 200 -or $jobReply.Body.Length -gt 8192){Fail 'JOB_REPLY_INVALID'}
 $jobSql="SELECT CASE WHEN json_valid(doc)=0 THEN 'INVALID' "+
  "WHEN json_type(doc)<>'object' THEN 'INVALID' "+
  "WHEN coalesce(json_type(doc,'$.id'),'')<>'text' "+
  "OR coalesce(json_type(doc,'$.query'),'')<>'text' "+
  "OR coalesce(json_type(doc,'$.entityType'),'')<>'text' "+
  "OR coalesce(json_type(doc,'$.limit'),'')<>'integer' THEN 'INVALID' "+
  "ELSE hex(CAST(json_extract(doc,'$.id') AS BLOB))||'|'||"+
  "hex(CAST(json_extract(doc,'$.query') AS BLOB))||'|'||"+
  "hex(CAST(json_extract(doc,'$.entityType') AS BLOB))||'|'||"+
  "json_extract(doc,'$.limit') END FROM j;"
 $parts=(JsonSql $jobReply.Body $jobSql).Split('|')
 if($parts.Length -ne 4){Fail 'JOB_NOT_OBJECT'}
 $id=DecodeHex $parts[0]
 $term=DecodeHex $parts[1]
 $kind=DecodeHex $parts[2]
 if($parts[3] -notmatch '^[0-9]{1,4}$'){Fail 'JOB_LIMIT_INVALID'}
 $limit=[int]$parts[3]
 if($id -notmatch '^[a-f0-9]{32}$'){Fail 'JOB_ID_INVALID'}
 if($term.Length -lt 3 -or $term.Length -gt 80 -or $term -match '[\x00-\x1f\x7f]'){Fail 'JOB_TERM_INVALID'}
 if($kind -ne 'COMPANY' -and $kind -ne 'CONTACT'){Fail 'JOB_TYPE_INVALID'}
 if($limit -ne 20){Fail 'JOB_LIMIT_INVALID'}
 $phase='LOCAL_SEARCH'
 $results=Search $term $kind $limit
 $validSql="SELECT CASE WHEN json_valid(doc)=0 THEN 'INVALID' "+
  "WHEN json_type(doc)<>'array' THEN 'INVALID' "+
  "WHEN json_array_length(doc)>20 THEN 'INVALID' "+
  "WHEN EXISTS(SELECT 1 FROM json_each(doc) AS e WHERE "+
  "CASE WHEN e.type<>'object' THEN 1 "+
  "WHEN coalesce(json_type(e.value,'$.id'),'')<>'text' "+
  "OR coalesce(json_type(e.value,'$.name'),'')<>'text' THEN 1 ELSE 0 END=1) "+
  "THEN 'INVALID' ELSE 'VALID' END FROM j;"
 if((JsonSql $results $validSql) -ne 'VALID'){Fail 'RESULT_ARRAY_INVALID'}
 $rowsSql="SELECT hex(CAST(json_extract(value,'$.id') AS BLOB))||'|'||"+
  "hex(CAST(json_extract(value,'$.name') AS BLOB)) "+
  "FROM json_each((SELECT doc FROM j));"
 $outItems=@()
 $rows=JsonSql $results $rowsSql
 if($rows.Length -gt 0){
  foreach($line in ($rows -split '\r?\n')){
   $pair=$line.Split('|')
   if($pair.Length -ne 2){Fail 'RESULT_ROW_INVALID'}
   $gid=DecodeHex $pair[0]
   $name=DecodeHex $pair[1]
   if($gid -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'){Fail 'RESULT_GUID_INVALID'}
   if($name.Length -lt 1 -or $name.Length -gt 256 -or $name -match '[\x00-\x1f\x7f]'){Fail 'RESULT_NAME_INVALID'}
   $outItems+=1
  }
 }
 if($outItems.Count -gt 20){Fail 'RESULT_COUNT_INVALID'}
 $phase='RETURN_BOUNDED_RESULTS'
 $payloadSql="SELECT hex(CAST(json_object('id','"+$id+
  "','items',json((SELECT json_group_array(json_object("+
  "'id',json_extract(value,'$.id'),'name',json_extract(value,'$.name'))) "+
  "FROM json_each(doc)))) AS BLOB)) FROM j;"
 $payload=ToAsciiJson (DecodeHex (JsonSql $results $payloadSql))
 $ack=Http 'POST' '/worker/result' $payload
 if($ack.Code -ne 204){Fail 'POST_NOT_ACKED'}
 'SEARCH_JOB_COMPLETED=YES'
 'SEARCH_RESULT_COUNT='+$outItems.Count
 'SEARCH_RESULT_MAX=20'
 'ONEC_CALLS=NO'
 'BITRIX_WRITES=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_SINGLE_OUTBOUND_POLL'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^WORKER_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_SINGLE_OUTBOUND_POLL;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}finally{
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
 if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
 $script:token=$null
}

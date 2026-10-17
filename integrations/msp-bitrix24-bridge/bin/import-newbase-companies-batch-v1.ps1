#requires -version 2
# Manually launched, bounded REAL company transfer from TEST NewBase SQLite snapshot.
# Continuation by source GUID cursor; no routine schedule, no production 1C access.
param([string]$ExpectedComputerName='SRV',[int]$MaxRows=20)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$phase='PRECHECK'
$script:root=$root
$script:cursorPath=Join-Path $root 'state\bitrix-newbase-company-v1.cursor'
$script:inflightPath=Join-Path $root 'state\bitrix-newbase-company-v1.inflight'
$script:heldPath=Join-Path $root 'state\bitrix-newbase-company-v1.held'
$script:logPath=Join-Path $root 'state\bitrix-newbase-company-v1.done'
$sourceDb=Join-Path $root 'data\customers.db'
$serviceSecret=Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'
$script:processed=0;$script:created=0;$script:existing=0;$script:held=0;$script:withReq=0
$secretBytes=$null;$decoded=$null;$script:base=$null;$cursor=''
function Fail([string]$Code){throw ('NEWBASE_'+$Code)}
function Quote([string]$Value){
 if($Value -match '[\x00-\x1f\x7f]'){Fail 'CONFIG_CONTROLS'}
 return ('"'+$Value.Replace('\','\\').Replace('"','\"')+'"')
}
function JsonQuote([string]$Value){
 $sb=New-Object Text.StringBuilder
 [void]$sb.Append('"')
 foreach($c in $Value.ToCharArray()){
  $n=[int]$c
  if($n -eq 34){[void]$sb.Append('\"')}
  elseif($n -eq 92){[void]$sb.Append('\\')}
  elseif($n -lt 32 -or $n -gt 126){[void]$sb.Append('\u'+$n.ToString('x4'))}
  else{[void]$sb.Append($c)}
 }
 [void]$sb.Append('"')
 return $sb.ToString()
}
function HexUtf8([string]$Value){return ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($Value))).Replace('-','')}
function Unhex([string]$Value){
 if(($Value.Length % 2) -ne 0 -or $Value -notmatch '^[A-F0-9]*$' -or $Value.Length -gt 1024){Fail 'HEX_INVALID'}
 $bytes=New-Object byte[] ($Value.Length/2)
 for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=[Convert]::ToByte($Value.Substring($i*2,2),16)}
 return [Text.Encoding]::UTF8.GetString($bytes)
}
function SqlJson([string]$Json,[string]$Select){
 if($Json.Length -gt 65536){Fail 'JSON_TOO_LARGE'}
 $cmd="WITH j(doc) AS (SELECT CAST(X'"+(HexUtf8 $Json)+"' AS TEXT)) "+$Select
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $script:root 'bin\sqlite3.exe'
 $i.Arguments='-batch -bail ":memory:"'
 $i.UseShellExecute=$false
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $i.CreateNoWindow=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'SQLITE_START'}
  $p.StandardInput.WriteLine($cmd);$p.StandardInput.Close()
  $result=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(10000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $result.Length -gt 1024){Fail 'SQLITE_PARSE'}
  return $result
 }finally{$p.Close()}
}
function Http([string]$Method,[string]$Body){
 if(@('crm.item.get','crm.item.list','crm.item.add','crm.requisite.list','crm.requisite.add','crm.requisite.get') -notcontains $Method){Fail 'UNAPPROVED_METHOD'}
 if($Body.Length -gt 8192 -or $Body -match '[^\x20-\x7e]'){Fail 'BODY_NOT_ASCII'}
 $cfg='url = '+(Quote ($script:base+$Method+'.json'))+[Environment]::NewLine
 $cfg+='request = "POST"'+[Environment]::NewLine
 $cfg+='header = "Content-Type: application/json"'+[Environment]::NewLine
 $cfg+='header = "Accept: application/json"'+[Environment]::NewLine
 $cfg+='data-binary = '+(Quote $Body)+[Environment]::NewLine
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $script:root 'bin\curl.exe'
 $ca=Join-Path $script:root 'config\curl-ca-bundle.crt'
 $i.Arguments='-q --silent --show-error --noproxy "*" --proto "=https" --tlsv1.2 --tls-max 1.2 --cacert "'+$ca+'" --max-redirs 0 --connect-timeout 10 --max-time 25 --write-out "__MSP_HTTP__:%{http_code}" --config -'
 $i.UseShellExecute=$false
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $i.CreateNoWindow=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'CURL_START'}
  $p.StandardInput.Write($cfg);$p.StandardInput.Close();$cfg=$null
  $utf8=New-Object IO.StreamReader -ArgumentList @($p.StandardOutput.BaseStream,[Text.Encoding]::UTF8,$true)
  $out=$utf8.ReadToEnd()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'CURL_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $out.Length -gt 65536){Fail 'CURL_FAILED'}
  $at=$out.LastIndexOf('__MSP_HTTP__:')
  if($at -lt 0 -or $out.Substring($at+13) -notmatch '^[0-9]{3}$'){Fail 'HTTP_STATUS_INVALID'}
  $code=[int]$out.Substring($at+13)
  if($code -ne 200){Fail ('HTTP_'+$code)}
  return $out.Substring(0,$at)
 }finally{$p.Close()}
}

function HexField([string]$Text){
 if($Text.Length -gt 1024 -or ($Text.Length%2) -ne 0 -or $Text -notmatch '^[0-9A-Fa-f]*$'){Fail 'SOURCE_HEX_INVALID'}
 return Unhex $Text
}
function LocalSql([string]$Query){
 $p=New-Object Diagnostics.Process
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $root 'bin\sqlite3.exe'
 $i.Arguments='-readonly -batch -bail "'+$sourceDb+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'SQL_SOURCE_START'}
  $p.StandardInput.WriteLine($Query);$p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(20000)){$p.Kill();Fail 'SQL_SOURCE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $out.Length -gt 65536){Fail 'SQL_SOURCE_READ'}
  return $out
 }finally{$p.Close()}
}
function Items([string]$Method,[string]$Filter,[string]$Select){
 $payload='{"entityTypeId":4,"filter":'+$Filter+',"select":'+$Select+',"start":0}'
 $json=Http $Method $payload
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN json_type(doc,'$.result.items')<>'array' THEN 'INVALID' WHEN json_array_length(doc,'$.result.items')>1 THEN 'MULTIPLE' WHEN coalesce(json_type(doc,'$.next'),'null')<>'null' THEN 'PAGING' WHEN json_array_length(doc,'$.result.items')=0 THEN 'NONE' WHEN json_type(doc,'$.result.items[0].id')='integer' THEN CAST(json_extract(doc,'$.result.items[0].id') AS TEXT) ELSE 'INVALID' END FROM j;"
 return SqlJson $json $sql
}
function Requisites([string]$Filter){
 $json=Http 'crm.requisite.list' ('{"filter":'+$Filter+',"select":["ID","ENTITY_ID","PRESET_ID","RQ_INN"],"start":0}')
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN json_type(doc,'$.result')<>'array' THEN 'INVALID' WHEN json_array_length(doc,'$.result')>1 THEN 'MULTIPLE' WHEN coalesce(json_type(doc,'$.next'),'null')<>'null' THEN 'PAGING' WHEN json_array_length(doc,'$.result')=0 THEN 'NONE' WHEN json_type(doc,'$.result[0].ID') IN ('integer','text') THEN CAST(json_extract(doc,'$.result[0].ID') AS TEXT) ELSE 'INVALID' END FROM j;"
 return SqlJson $json $sql
}
function Record([string]$Path,[string]$Value,[bool]$Append){
 if($Append){[IO.File]::AppendAllText($Path,$Value+[Environment]::NewLine,[Text.Encoding]::ASCII)}
 else{[IO.File]::WriteAllText($Path,$Value,[Text.Encoding]::ASCII)}
}
function Cursor([string]$Guid,[string]$State,[string]$CrmId,[string]$ReqId){
 $line=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+'|'+$Guid+'|'+$State+'|'+$CrmId+'|'+$ReqId
 if($State -eq 'HELD'){Record $script:heldPath $line $true}else{Record $script:logPath $line $true}
 Record $script:cursorPath $Guid $false
 $script:processed++
}
function InFlight([string]$Guid,[string]$State,[string]$Id){
 Record $script:inflightPath ($Guid+'|'+$State+'|'+$Id) $false
}
function VerifyCompany([string]$Id,[string]$Guid,[string]$Name){
 $reply=Http 'crm.item.get' ('{"entityTypeId":4,"id":'+$Id+'}')
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN CAST(json_extract(doc,'$.result.item.id') AS TEXT)='"+$Id+"' AND json_extract(doc,'$.result.item.originatorId')='MSP_ONEC_NEWBASE' AND json_extract(doc,'$.result.item.originId')='"+$Guid+"' AND hex(CAST(json_extract(doc,'$.result.item.title') AS BLOB))='"+(HexUtf8 $Name)+"' THEN 'OK' ELSE 'MISMATCH' END FROM j;"
 if((SqlJson $reply $sql) -ne 'OK'){Fail 'COMPANY_BACKREAD_MISMATCH'}
}
function VerifyRequisite([string]$ReqId,[string]$Id,[string]$Inn){
 $reply=Http 'crm.requisite.get' ('{"id":'+$ReqId+'}')
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN CAST(json_extract(doc,'$.result.ENTITY_ID') AS TEXT)='"+$Id+"' AND hex(CAST(coalesce(json_extract(doc,'$.result.RQ_INN'),'') AS BLOB))='"+(HexUtf8 $Inn)+"' THEN 'OK' ELSE 'MISMATCH' END FROM j;"
 if((SqlJson $reply $sql) -ne 'OK'){Fail 'REQUISITE_BACKREAD_MISMATCH'}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if($MaxRows -lt 1 -or $MaxRows -gt 50){Fail 'MAX_ROWS_NOT_ALLOWED'}
 $who=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
 if($who.User.Value -ne 'S-1-5-19' -and -not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_OR_SERVICE_REQUIRED'}
 if([IO.File]::Exists($script:inflightPath)){Fail 'UNRESOLVED_INFLIGHT_STOP'}
 foreach($f in @($sourceDb,$serviceSecret,(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'bin\curl.exe'),(Join-Path $root 'config\curl-ca-bundle.crt'),(Join-Path $root 'state\bitrix-company03-requisite-once-status.txt'))){
  if(-not [IO.File]::Exists($f) -or ([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint)){Fail 'SOURCE_PREREQUISITE_MISSING'}
 }
 $proof=[IO.File]::ReadAllText((Join-Path $root 'state\bitrix-company03-requisite-once-status.txt'),[Text.Encoding]::ASCII)
 if($proof -notmatch ';STAGE=PASS;COMPANY_ID=3;REQUISITE_ID=1$'){Fail 'FIRST_REQUISITE_NOT_ACCEPTED'}
 if((LocalSql 'PRAGMA quick_check;') -ne 'ok'){Fail 'LOCAL_DB_INTEGRITY'}
 $counts=LocalSql "SELECT count(*)||':'||sum(onec_type='LEGAL')||':'||sum(onec_type='PERSON')||':'||sum(onec_type='REVIEW') FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;"
 if($counts -ne '6433:1941:4486:6'){Fail 'SOURCE_COUNTS_CHANGED'}
 if([IO.File]::Exists($script:cursorPath)){
  $cursor=[IO.File]::ReadAllText($script:cursorPath,[Text.Encoding]::ASCII).Trim()
  if($cursor -notmatch '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$'){Fail 'CURSOR_INVALID'}
 }
 $phase='DECRYPT_DPAPI'
 Add-Type -AssemblyName System.Security
 $secretBytes=[IO.File]::ReadAllBytes($serviceSecret)
 $decoded=[Security.Cryptography.ProtectedData]::Unprotect($secretBytes,[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-Bitrix24-Direct-Webhook-v1'),[Security.Cryptography.DataProtectionScope]::LocalMachine)
 $tokenText=[Text.Encoding]::UTF8.GetString($decoded)
 if($tokenText -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/?$'){Fail 'WEBHOOK_FORMAT_INVALID'}
 $script:base=$tokenText.TrimEnd('/')+'/'
 $tokenText=$null
 $phase='SOURCE_ROWS'
 $predicate="onec_type='LEGAL' AND buyer=1 AND deletion_mark=0 AND invalid=0 AND coalesce(needs_review,0)=0"
 if($cursor.Length -gt 0){$predicate+=" AND onec_guid>'"+$cursor+"'"}
 $query="SELECT lower(onec_guid)||'|'||hex(CAST(coalesce(nullif(trim(name_short),''),trim(name_full),'') AS BLOB))||'|'||hex(CAST(coalesce(trim(name_full),'') AS BLOB))||'|'||hex(CAST(coalesce(trim(inn),'') AS BLOB)) FROM customers WHERE "+$predicate+" ORDER BY onec_guid LIMIT "+$MaxRows+";"
 $lines=(LocalSql $query)
 if($lines.Length -eq 0){
  'COMPANY_SOURCE_EXHAUSTED=YES'
  'RESULT=PASS;STAGE=NEWBASE_COMPANY_BATCH_V1'
  exit 0
 }
 foreach($line in ($lines -split '\r?\n')){
  $parts=$line.Split('|')
  if($parts.Length -ne 4){Fail 'ROW_PARSE'}
  $guid=$parts[0]
  if($guid -notmatch '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$'){Fail 'GUID_INVALID'}
  $phase='PROCESS_SOURCE_ROW'
  $name=HexField $parts[1];$full=HexField $parts[2];$inn=HexField $parts[3]
  if($name.Length -lt 3 -or $name.Length -gt 140 -or $full.Length -gt 256 -or $inn.Length -gt 12){
   Cursor $guid 'HELD' '0' '0';$script:held++;continue
  }
  if($full.Length -eq 0){$full=$name}
  if($inn.Length -ne 0 -and $inn -notmatch '^(?:[0-9]{10}|[0-9]{12})$'){
   Cursor $guid 'HELD' '0' '0';$script:held++;continue
  }
  $origin=Items 'crm.item.list' ('{"originatorId":"MSP_ONEC_NEWBASE","originId":"'+$guid+'"}') '["id"]'
  if($origin -eq 'INVALID' -or $origin -eq 'MULTIPLE' -or $origin -eq 'PAGING'){Fail 'ORIGIN_QUERY_UNCERTAIN'}
  $newCompany=$false
  if($origin -eq 'NONE'){
   $nameMatch=Items 'crm.item.list' ('{"title":'+(JsonQuote $name)+'}') '["id"]'
   if($nameMatch -eq 'INVALID' -or $nameMatch -eq 'PAGING'){Fail 'NAME_QUERY_UNCERTAIN'}
   if($nameMatch -ne 'NONE'){Cursor $guid 'HELD' '0' '0';$script:held++;continue}
   if($inn.Length -gt 0){
    $otherReq=Requisites ('{"RQ_INN":'+(JsonQuote $inn)+'}')
    if($otherReq -eq 'INVALID' -or $otherReq -eq 'PAGING'){Fail 'INN_QUERY_UNCERTAIN'}
    if($otherReq -ne 'NONE'){Cursor $guid 'HELD' '0' '0';$script:held++;continue}
   }
   $phase='ADD_COMPANY'
   InFlight $guid 'BEFORE_COMPANY_ADD' '0'
   $payload='{"entityTypeId":4,"fields":{"title":'+(JsonQuote $name)+',"originatorId":"MSP_ONEC_NEWBASE","originId":"'+$guid+'","opened":"N"}}'
   $reply=Http 'crm.item.add' $payload
   $id=SqlJson $reply "SELECT CASE WHEN json_valid(doc)=1 AND json_type(doc,'$.result.item.id')='integer' THEN CAST(json_extract(doc,'$.result.item.id') AS TEXT) ELSE 'INVALID' END FROM j;"
   if($id -notmatch '^[1-9][0-9]{0,9}$'){Fail 'COMPANY_ADD_UNCERTAIN'}
   InFlight $guid 'COMPANY_CREATED' $id
   $newCompany=$true
  }else{$id=$origin}
  $phase='VERIFY_COMPANY'
  VerifyCompany $id $guid $name
  $reqId='0'
  if($inn.Length -gt 0){
   $phase='READ_REQUISITES'
   $existingReq=Requisites ('{"ENTITY_TYPE_ID":4,"ENTITY_ID":'+$id+'}')
   if($existingReq -eq 'INVALID' -or $existingReq -eq 'MULTIPLE' -or $existingReq -eq 'PAGING'){Fail 'REQUISITES_UNCERTAIN'}
   if($existingReq -eq 'NONE'){
    if(-not [IO.File]::Exists($script:inflightPath)){InFlight $guid 'BEFORE_REQUISITE_ADD' $id}
    else{InFlight $guid 'BEFORE_REQUISITE_ADD' $id}
    $payload='{"fields":{"ENTITY_TYPE_ID":4,"ENTITY_ID":'+$id+',"PRESET_ID":1,"NAME":'+(JsonQuote $name)+',"RQ_COMPANY_NAME":'+(JsonQuote $name)+',"RQ_COMPANY_FULL_NAME":'+(JsonQuote $full)+',"RQ_INN":'+(JsonQuote $inn)+'}}'
    $reply=Http 'crm.requisite.add' $payload
    $reqId=SqlJson $reply "SELECT CASE WHEN json_valid(doc)=1 AND json_type(doc,'$.result')='integer' THEN CAST(json_extract(doc,'$.result') AS TEXT) ELSE 'INVALID' END FROM j;"
    if($reqId -notmatch '^[1-9][0-9]{0,9}$'){Fail 'REQUISITE_ADD_UNCERTAIN'}
    InFlight $guid 'REQUISITE_CREATED' $reqId
   }else{$reqId=$existingReq}
   $phase='VERIFY_REQUISITE'
   VerifyRequisite $reqId $id $inn
   $script:withReq++
  }
  $phase='COMMIT_PROGRESS'
  Cursor $guid 'PASS' $id $reqId
  if([IO.File]::Exists($script:inflightPath)){[IO.File]::Delete($script:inflightPath)}
  if($newCompany){$script:created++}else{$script:existing++}
  Start-Sleep -Milliseconds 200
 }
 'SOURCE_ROWS_PROCESSED='+$script:processed
 'COMPANIES_CREATED='+$script:created
 'COMPANIES_ALREADY_LINKED='+$script:existing
 'ROWS_HELD_FOR_REVIEW='+$script:held
 'REQUISITES_VERIFIED='+$script:withReq
 'CONTINUATION_CURSOR_SAVED=YES'
 'ONEC_NEWBASE_WRITES=NO'
 'SOURCE_SQLITE_WRITES=NO'
 'RESULT=PASS;STAGE=NEWBASE_COMPANY_BATCH_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=NEWBASE_COMPANY_BATCH_V1;GATE='+$gate+';PHASE='+$phase
 'SOURCE_ROWS_PROCESSED='+$script:processed
 'COMPANIES_CREATED='+$script:created
 'ROWS_HELD_FOR_REVIEW='+$script:held
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}finally{
 if($null -ne $secretBytes){[Array]::Clear($secretBytes,0,$secretBytes.Length)}
 if($null -ne $decoded){[Array]::Clear($decoded,0,$decoded.Length)}
 $script:base=$null
}
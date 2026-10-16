#requires -version 2
# Explicitly authorized one real TEST NewBase customer company -> CRM with origin/requisite backread.
# No 1C or SQLite writes; machine DPAPI Bitrix webhook; never logs secret or customer fields.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$receipt=Join-Path $root 'state\bitrix-testnewbase-real-company-01.txt'
$phase='PRECHECK'
$secure=$null
$ptr=[IntPtr]::Zero
$base=$null
$tokenText=$null
$createdId=$null
$script:sourceGuid=''
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
 if(@('crm.item.add','crm.item.get','crm.item.list','crm.requisite.add','crm.requisite.get','crm.requisite.list') -notcontains $Method){Fail 'UNAPPROVED_METHOD'}
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
  $out=$p.StandardOutput.ReadToEnd()
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
function WriteState([string]$State){
 $msg='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS='+$State+';MARKER='+$script:sourceGuid
 if($null -ne $script:createdId){$msg+=';CREATED_ID='+$script:createdId}
 [IO.File]::WriteAllText($script:receipt,$msg,[Text.Encoding]::ASCII)
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([IO.File]::Exists($receipt)){Fail 'PRIOR_RUN_DIAGNOSE_FIRST'}
 $script:root=$root
 foreach($required in @('data\customers.db','bin\sqlite3.exe','bin\curl.exe','config\curl-ca-bundle.crt','state\bitrix-localservice-api-readonly-v2-status.txt','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi')){
  if(-not [IO.File]::Exists((Join-Path $root $required))){Fail 'COMPONENT_MISSING'}
 }
 $db=Join-Path $root 'data\customers.db'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 $phase='SELECT_SOURCE'
 $query="SELECT onec_guid||'|'||hex(CAST(coalesce(nullif(trim(name_short),''),trim(name_full)) AS BLOB))||'|'||hex(CAST(coalesce(trim(name_full),'') AS BLOB))||'|'||hex(CAST(trim(inn) AS BLOB)) FROM customers WHERE onec_type='LEGAL' AND buyer=1 AND deletion_mark=0 AND invalid=0 AND needs_review=0 AND length(trim(coalesce(nullif(name_short,''),name_full,''))) BETWEEN 3 AND 140 AND (length(trim(inn))=10 OR length(trim(inn))=12) AND trim(inn) NOT GLOB '*[^0-9]*' ORDER BY onec_guid LIMIT 1;"
 $rows=@(& $sqlite -readonly -batch -bail $db $query 2>&1)
 if($LASTEXITCODE -ne 0 -or $rows.Count -ne 1){Fail 'LOCAL_SQLITE_READ_FAILED'}
 $parts=($rows[0].ToString().Trim()).Split('|')
 if($parts.Length -ne 4){Fail 'NO_VALID_TEST_COMPANY'}
 $script:sourceGuid=$parts[0].ToLowerInvariant()
 if($script:sourceGuid -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'){Fail 'GUID_INVALID'}
 $name=Unhex $parts[1];$full=Unhex $parts[2];$tax=Unhex $parts[3]
 if($name.Length -lt 3 -or $name.Length -gt 140 -or $tax -notmatch '^([0-9]{10}|[0-9]{12})$'){Fail 'SOURCE_FIELDS_INVALID'}
 if($full.Trim().Length -eq 0){$full=$name}
 $phase='DECRYPT_WEBHOOK'
 Add-Type -AssemblyName System.Security
 $bytes=[IO.File]::ReadAllBytes((Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'))
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-Bitrix24-Direct-Webhook-v1')
 $decoded=$null
 try{
  $decoded=[Security.Cryptography.ProtectedData]::Unprotect($bytes,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $tokenText=[Text.Encoding]::UTF8.GetString($decoded)
 }finally{if($null -ne $decoded){[Array]::Clear($decoded,0,$decoded.Length)};[Array]::Clear($bytes,0,$bytes.Length)}
 if($tokenText -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/?$'){Fail 'WEBHOOK_FORMAT'}
 $script:base=$tokenText.TrimEnd('/')+'/'
 $tokenText=$null
 $phase='DEDUPE_BY_ORIGIN'
 $found=Http 'crm.item.list' ('{"entityTypeId":4,"filter":{"originatorId":"MSP_ONEC_NEWBASE","originId":"'+$script:sourceGuid+'"},"select":["id"],"start":0}')
 $count=SqlJson $found "SELECT CASE WHEN json_valid(doc)=1 AND json_type(doc,'$.result.items')='array' THEN CAST(json_array_length(doc,'$.result.items') AS TEXT) ELSE 'INVALID' END FROM j;"
 if($count -ne '0'){Fail 'ORIGIN_EXISTS_OR_API_UNEXPECTED'}
 $phase='DEDUPE_BY_NAME'
 $found=Http 'crm.item.list' ('{"entityTypeId":4,"filter":{"title":'+(JsonQuote $name)+'},"select":["id"],"start":0}')
 $count=SqlJson $found "SELECT CASE WHEN json_valid(doc)=1 AND json_type(doc,'$.result.items')='array' THEN CAST(json_array_length(doc,'$.result.items') AS TEXT) ELSE 'INVALID' END FROM j;"
 if($count -ne '0'){Fail 'COMPANY_TITLE_EXISTS_OR_API_UNEXPECTED'}
 $phase='DEDUPE_BY_INN'
 $found=Http 'crm.requisite.list' ('{"filter":{"RQ_INN":'+(JsonQuote $tax)+'},"select":["ID"],"start":0}')
 $count=SqlJson $found "SELECT CASE WHEN json_valid(doc)=1 AND json_type(doc,'$.result')='array' THEN CAST(json_array_length(doc,'$.result') AS TEXT) ELSE 'INVALID' END FROM j;"
 if($count -ne '0'){Fail 'INN_EXISTS_OR_API_UNEXPECTED'}
 $phase='ADD_REAL_COMPANY'
 WriteState 'BEFORE_ADD'
 $add='{"entityTypeId":4,"fields":{"title":'+(JsonQuote $name)+',"originatorId":"MSP_ONEC_NEWBASE","originId":"'+$script:sourceGuid+'","opened":"N"}}'
 $reply=Http 'crm.item.add' $add
 $id=SqlJson $reply "SELECT CASE WHEN json_valid(doc)=1 AND json_type(doc,'$.result.item.id')='integer' THEN CAST(json_extract(doc,'$.result.item.id') AS TEXT) ELSE 'INVALID' END FROM j;"
 if($id -notmatch '^[1-9][0-9]{0,9}$'){Fail 'ADD_UNCONFIRMED'}
 $script:createdId=[int]$id
 WriteState 'COMPANY_CREATED'
 $phase='BACKREAD_COMPANY'
 $got=Http 'crm.item.get' ('{"entityTypeId":4,"id":'+$script:createdId+'}')
 $verified=SqlJson $got "SELECT CASE WHEN CAST(json_extract(doc,'$.result.item.id') AS TEXT)='"+$id+"' AND json_extract(doc,'$.result.item.originId')='"+$script:sourceGuid+"' AND json_extract(doc,'$.result.item.originatorId')='MSP_ONEC_NEWBASE' THEN 'PASS' ELSE 'FAIL' END FROM j;"
 if($verified -ne 'PASS'){Fail 'COMPANY_BACKREAD_FAILED'}
 $phase='ADD_COMPANY_REQUISITE'
 WriteState 'BEFORE_REQUISITE'
 $body='{"fields":{"ENTITY_TYPE_ID":4,"ENTITY_ID":'+$script:createdId+',"PRESET_ID":1,"NAME":'+(JsonQuote $name)+',"RQ_COMPANY_NAME":'+(JsonQuote $name)+',"RQ_COMPANY_FULL_NAME":'+(JsonQuote $full)+',"RQ_INN":'+(JsonQuote $tax)+'}}'
 $got=Http 'crm.requisite.add' $body
 $reqid=SqlJson $got "SELECT CASE WHEN json_valid(doc)=1 AND json_type(doc,'$.result')='integer' THEN CAST(json_extract(doc,'$.result') AS TEXT) ELSE 'INVALID' END FROM j;"
 if($reqid -notmatch '^[1-9][0-9]{0,9}$'){Fail 'REQUISITE_ADD_UNCONFIRMED'}
 WriteState 'REQUISITE_CREATED'
 $phase='BACKREAD_REQUISITE'
 $got=Http 'crm.requisite.get' ('{"id":'+$reqid+'}')
 $expected=SqlJson $got "SELECT CASE WHEN json_valid(doc)=1 AND CAST(json_extract(doc,'$.result.ENTITY_ID') AS TEXT)='"+$id+"' AND json_extract(doc,'$.result.RQ_INN')='"+$tax+"' THEN 'PASS' ELSE 'FAIL' END FROM j;"
 if($expected -ne 'PASS'){Fail 'REQUISITE_BACKREAD_FAILED'}
 WriteState 'PASS'
 'REAL_TEST_NEWBASE_COMPANY=PASS'
 'BITRIX_COMPANY_ID='+$id
 'BITRIX_REQUISITE_ID='+$reqid
 'COMPANY_SOURCE_GUID_REGISTERED=YES'
 'SOURCE_1C_WRITES=NO'
 'SOURCE_SQLITE_WRITES=NO'
 'RESULT=PASS;STAGE=BITRIX_NEWBASE_REAL_COMPANY_01'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($script:sourceGuid.Length -gt 0){
  try{WriteState ('FAIL_'+$gate)}catch{}
 }
 'RESULT=FAIL;STAGE=BITRIX_NEWBASE_REAL_COMPANY_01;GATE='+$gate+';PHASE='+$phase
 if($null -ne $script:createdId){'NEWBASE_COMPANY_ID='+$script:createdId}
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}finally{
 if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 $secure=$null
 $tokenText=$null
 $script:base=$null
}
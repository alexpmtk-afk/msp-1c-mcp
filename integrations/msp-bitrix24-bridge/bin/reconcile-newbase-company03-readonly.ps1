#requires -version 2
# One-shot READ ONLY diagnosis of the already-created NewBase CRM company ID 3.
# Never create, update, delete, list other customers, or print sensitive fields.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$receipt=Join-Path $root 'state\bitrix-testnewbase-real-company-01.txt'
$phase='PRECHECK'
$secretBytes=$null
$decoded=$null
$tokenText=$null
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
 if(@('crm.item.get','crm.requisite.list') -notcontains $Method){Fail 'UNAPPROVED_METHOD'}
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
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $script:root=$root
 if(-not [IO.File]::Exists($receipt)){Fail 'SOURCE_RECEIPT_MISSING'}
 $state=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 if($state -match '^UTC=[^;]+;STATUS=FAIL_SQLITE_PARSE;MARKER=([a-f0-9-]{36});CREATED_ID=3$'){$sourceGuid=$Matches[1]}else{Fail 'SOURCE_RECEIPT_UNEXPECTED'}
 if($sourceGuid -notmatch '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$'){Fail 'SOURCE_GUID_INVALID'}
 $db=Join-Path $root 'data\customers.db'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 if(-not [IO.File]::Exists($db) -or -not [IO.File]::Exists($sqlite)){Fail 'SQLITE_MISSING'}
 $lookup="SELECT count(*) FROM customers WHERE onec_guid='"+$sourceGuid+"' AND onec_type='LEGAL' AND buyer=1 AND deletion_mark=0 AND invalid=0;"
 $n=@(& $sqlite -readonly -batch -bail $db $lookup 2>&1)
 if($LASTEXITCODE -ne 0 -or $n.Count -ne 1 -or ([string]$n[0]).Trim() -ne '1'){Fail 'SOURCE_ROW_NOT_CONFIRMED'}
 $phase='DPAPI'
 Add-Type -AssemblyName System.Security
 $secretBytes=[IO.File]::ReadAllBytes((Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'))
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-Bitrix24-Direct-Webhook-v1')
 $decoded=[Security.Cryptography.ProtectedData]::Unprotect($secretBytes,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 $tokenText=[Text.Encoding]::UTF8.GetString($decoded)
 if($tokenText -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/?$'){Fail 'WEBHOOK_FORMAT'}
 $script:base=$tokenText.TrimEnd('/')+'/'
 $tokenText=$null
 $phase='READ_EXISTING_COMPANY_3'
 $answer=Http 'crm.item.get' '{"entityTypeId":4,"id":3}'
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN CAST(json_extract(doc,'$.result.item.id') AS TEXT)='3' AND json_extract(doc,'$.result.item.originatorId')='MSP_ONEC_NEWBASE' AND json_extract(doc,'$.result.item.originId')='"+$sourceGuid+"' THEN 'MATCH' ELSE 'NOT_MATCHED' END FROM j;"
 $company=SqlJson $answer $sql
 $answer=$null
 if($company -ne 'MATCH'){
  'COMPANY_3_SOURCE_MATCH=NO_OR_UNCONFIRMED'
  'CRM_WRITES=NO'
  'RESULT=FAIL;STAGE=NEWBASE_COMPANY03_READONLY_RECONCILE;GATE=COMPANY_MAPPING_MISMATCH'
  exit 1
 }
 $phase='READ_COMPANY_REQUISITES'
 $answer=Http 'crm.requisite.list' '{"filter":{"ENTITY_TYPE_ID":4,"ENTITY_ID":3},"select":["ID","ENTITY_ID","PRESET_ID"],"start":0}'
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN json_type(doc,'$.result')<>'array' THEN 'INVALID' WHEN json_array_length(doc,'$.result')>50 THEN 'INVALID' ELSE CAST(json_array_length(doc,'$.result') AS TEXT) END FROM j;"
 $count=SqlJson $answer $sql
 $answer=$null
 if($count -notmatch '^[0-9]{1,2}$'){Fail 'REQUISITES_RESPONSE_UNEXPECTED'}
 'COMPANY_3_SOURCE_MATCH=PASS'
 'SOURCE_GUID_MATCH=YES'
 'COMPANY_REQUISITES_COUNT='+$count
 'CRM_WRITES=NO'
 'SOURCE_1C_WRITES=NO'
 'SOURCE_SQLITE_WRITES=NO'
 'RESULT=PASS;STAGE=NEWBASE_COMPANY03_READONLY_RECONCILE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=NEWBASE_COMPANY03_READONLY_RECONCILE;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}finally{
 if($null -ne $secretBytes){[Array]::Clear($secretBytes,0,$secretBytes.Length)}
 if($null -ne $decoded){[Array]::Clear($decoded,0,$decoded.Length)}
 $tokenText=$null;$script:base=$null
}
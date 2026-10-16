#requires -version 2
# One-shot LOCAL SERVICE only Bitrix24 REST read-only proof using encrypted webhook on physical SRV.
# Decrypt enrolled machine webhook without prompt, never print or store its plaintext.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$receipt=Join-Path $root 'state\bitrix-localservice-api-readonly-status.txt'
$plain=$null
$secure=$null
$ptr=[IntPtr]::Zero
$cfg=$null
$bodyReply=$null
$phase='PRECHECK'
function Fail([string]$Code){throw ('DIRECT_CRM_'+$Code)}
function Quote([string]$Value){
 if($Value -match '[\x00-\x1f\x7f]'){Fail 'CONTROL_IN_CONFIG'}
 return ('"'+$Value.Replace('\','\\').Replace('"','\"')+'"')
}
function JsonSql([string]$Json,[string]$Select){
 if($Json.Length -gt 65536){Fail 'JSON_SIZE'}
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
  if(-not $p.Start()){Fail 'SQLITE_START'}
  $p.StandardInput.WriteLine($sql)
  $p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(10000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $out.Length -gt 128){Fail 'SQLITE_PARSE'}
  return $out
 }finally{$p.Close()}
}
function HttpOnce([string]$Url,[string]$Payload){
 $script:cfg='url = '+(Quote $Url)+[Environment]::NewLine
 $script:cfg+='request = "POST"'+[Environment]::NewLine
 $script:cfg+='header = "Content-Type: application/json"'+[Environment]::NewLine
 $script:cfg+='header = "Accept: application/json"'+[Environment]::NewLine
 $script:cfg+='data-binary = '+(Quote $Payload)+[Environment]::NewLine
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $script:root 'bin\curl.exe'
 $ca=Join-Path $script:root 'config\curl-ca-bundle.crt'
 $i.Arguments='-q --silent --show-error --noproxy "*" --proto "=https" --tlsv1.2 --tls-max 1.2 --cacert "'+$ca+'" --max-redirs 0 --connect-timeout 10 --max-time 25 --write-out "__MSP_HTTP__:%{http_code}" --config -'
 $i.UseShellExecute=$false
 $i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'CURL_START'}
  $p.StandardInput.Write($script:cfg)
  $p.StandardInput.Close()
  $script:cfg=$null
  $raw=$p.StandardOutput.ReadToEnd()
  $ignored=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'CURL_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $raw.Length -gt 65536){Fail 'CURL_FAILED'}
  $idx=$raw.LastIndexOf('__MSP_HTTP__:')
  if($idx -lt 0 -or $raw.Substring($idx+13) -notmatch '^[0-9]{3}$'){Fail 'HTTP_STATUS_INVALID'}
  $http=[int]::Parse($raw.Substring($idx+13))
  if($http -ne 200){Fail 'HTTP_NOT_200'}
  return $raw.Substring(0,$idx)
 }finally{$p.Close()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 $serviceProof=Join-Path $root 'state\bitrix-localservice-dpapi-status.txt'
 if(-not [IO.File]::Exists($serviceProof)){Fail 'SERVICE_DPAPI_PROOF_MISSING'}
 $textProof=[IO.File]::ReadAllText($serviceProof,[Text.Encoding]::ASCII).Trim()
 if($textProof -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;DPAPI_UNPROTECT=PASS;WEBHOOK_HOST=VALID;SECRET_PRINTED=NO;BITRIX_CALLS=0;ONEC_CALLS=0$'){Fail 'SERVICE_DPAPI_PROOF_NOT_ACCEPTED'}
 $manualProof=Join-Path $root 'state\bitrix-direct-enrolled-webhook-api-readonly-status.txt'
 if(-not [IO.File]::Exists($manualProof)){Fail 'MANUAL_API_PROOF_MISSING'}
 $manualText=[IO.File]::ReadAllText($manualProof,[Text.Encoding]::ASCII).Trim()
 if($manualText -notmatch '^UTC=[^;]+;STATUS=PASS;TARGET=b24-uwmjda\.bitrix24\.ru;METHOD=crm\.requisite\.preset\.field\.list;PRESET_ID=1;FIELD_COUNT=13;RQ_INN=1;RQ_KPP=1;RQ_OGRN=1;RQ_COMPANY_NAME=1;RQ_COMPANY_FULL_NAME=1;CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=YES_ENCRYPTED$'){Fail 'MANUAL_API_PROOF_NOT_ACCEPTED'}
 if([IO.File]::Exists($receipt)){Fail 'ALREADY_TESTED_DIAGNOSE_FIRST'}
 foreach($f in @('bin\curl.exe','bin\sqlite3.exe','config\curl-ca-bundle.crt','state\bitrix-direct-https-smoke-status.txt')){
  $file=Join-Path $root $f
  if(-not [IO.File]::Exists($file)){Fail 'PREREQUISITE_MISSING'}
  if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 $https=[IO.File]::ReadAllText((Join-Path $root 'state\bitrix-direct-https-smoke-status.txt'),[Text.Encoding]::ASCII).Trim()
 if($https -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;TARGET=b24-uwmjda.bitrix24.ru;TLS_VERIFY=PASS;HTTP_STATUS=[0-9]{3};CUSTOMERS=6433;INDEX=6433;WORKER_ENABLED=NO;REST_CALLS=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0$'){Fail 'HTTPS_NOT_ACCEPTED'}
 # Old proven preset receipt remains immutable; it must not be replayed or overwritten.
 $previousReceipt=Join-Path $root 'state\bitrix-direct-company-preset-fields-readonly-status.txt'
 if(-not [IO.File]::Exists($previousReceipt)){Fail 'PREVIOUS_PRESET_RECEIPT_MISSING'}
 $previous=[IO.File]::ReadAllText($previousReceipt,[Text.Encoding]::ASCII).Trim()
 if($previous -notmatch '^UTC=[^;]+;STATUS=PASS;TARGET=b24-uwmjda\.bitrix24\.ru;METHOD=crm\.requisite\.preset\.field\.list;PRESET_ID=1;FIELD_COUNT=13;RQ_INN=1;RQ_KPP=1;RQ_OGRN=1;RQ_COMPANY_NAME=1;RQ_COMPANY_FULL_NAME=1;CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=NO$'){Fail 'PREVIOUS_PRESET_RECEIPT_UNEXPECTED'}
 $presetReceipt=Join-Path $root 'state\bitrix-direct-requisite-preset-details-status.txt'
 if(-not [IO.File]::Exists($presetReceipt)){Fail 'PRESET_DETAILS_NOT_VERIFIED'}
 $verified=[IO.File]::ReadAllText($presetReceipt,[Text.Encoding]::ASCII).Trim()
 if($verified -notmatch ';STATUS=PASS;TARGET=b24-uwmjda.bitrix24.ru;METHOD=crm.requisite.preset.list;DETAILS_COUNT=3;CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=NO$'){Fail 'PRESET_DETAILS_NOT_VERIFIED'}
 foreach($f in @('config\bitrix-search-worker.ini','secrets\bitrix-search-worker.dpapi')){
  if([IO.File]::Exists((Join-Path $root $f))){Fail 'LEGACY_RELAY_WORKER_CONFIGURED'}
 }
 # Use the enrolled encrypted webhook. Never prompt again and never log the URL.
 $enrollment=Join-Path $root 'state\bitrix-direct-webhook-enrolled.txt'
 $secret=Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'
 $privateDir=Join-Path $root 'staging\bitrix-direct-private'
 if(-not [IO.File]::Exists($enrollment) -or -not [IO.File]::Exists($secret)){Fail 'WEBHOOK_NOT_ENROLLED'}
 foreach($item in @($privateDir,$secret)){
  if(([IO.File]::GetAttributes($item) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'SECRET_REPARSE'}
 }
 $proof=[IO.File]::ReadAllText($enrollment,[Text.Encoding]::ASCII).Trim()
 if($proof -notmatch '^UTC=[^;]+;STATUS=PASS;SECRET=bitrix-direct-private/bitrix-direct-webhook.dpapi;STORAGE=MACHINE_DPAPI;READERS=SYSTEM_ADMINS_LOCAL_SERVICE_ENROLLER;WEBHOOK_PRINTED=NO;COLLECTOR_ENABLED=NO;BITRIX_CALLS=0;ONEC_CALLS=0$'){Fail 'ENROLLMENT_PROOF_MISMATCH'}
 $acl=[IO.File]::GetAccessControl($secret)
 $readers=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
 $serviceReader=$false
 $currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 foreach($rule in $readers){
  if($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){continue}
  if(@('S-1-5-18','S-1-5-19','S-1-5-32-544',$currentSid) -notcontains $rule.IdentityReference.Value){Fail 'SECRET_PERMISSIONS_INVALID'}
  if($rule.IdentityReference.Value -eq 'S-1-5-19'){$serviceReader=$true}
 }
 if(-not $serviceReader){Fail 'SERVICE_READER_MISSING'}
 Add-Type -AssemblyName System.Security
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-Bitrix24-Direct-Webhook-v1')
 $sealed=[IO.File]::ReadAllBytes($secret)
 if($sealed.Length -lt 64 -or $sealed.Length -gt 4096){Fail 'SECRET_LENGTH_INVALID'}
 $decoded=$null
 try{
  $decoded=[Security.Cryptography.ProtectedData]::Unprotect($sealed,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $plain=[Text.Encoding]::UTF8.GetString($decoded)
 }finally{
  if($null -ne $decoded){[Array]::Clear($decoded,0,$decoded.Length)}
  [Array]::Clear($sealed,0,$sealed.Length)
 }
 if($plain -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/?$'){Fail 'WEBHOOK_HOST_OR_FORMAT_INVALID'}
 $url=$plain.TrimEnd('/')+'/crm.requisite.preset.field.list.json'
 $payload='{"preset":{"ID":1},"start":0}'
 $phase='READONLY_BITRIX_REST'
 $script:bodyReply=HttpOnce $url $payload
 $url=$null
 $plain=$null
 $sql="SELECT CASE WHEN json_valid(doc)=0 THEN 'INVALID' "+
  "WHEN json_type(doc)<>'object' THEN 'INVALID' "+
  "WHEN coalesce(json_type(doc,'$.error'),'')='text' THEN 'API_ERROR' "+
  "WHEN coalesce(json_type(doc,'$.result'),'')<>'array' THEN 'BAD_RESULT' "+
  "WHEN json_array_length(doc,'$.result')>50 THEN 'PAGE_TOO_LARGE' "+
  "WHEN coalesce(json_type(doc,'$.next'),'null')<>'null' THEN 'PAGING_PRESENT' "+
  "ELSE 'OK|'||json_array_length(doc,'$.result')||'|'||"+
  "coalesce(CAST(json_extract(doc,'$.total') AS TEXT),'UNKNOWN') END FROM j;"
 $parsed=JsonSql $script:bodyReply $sql
 if($parsed -notmatch '^OK\|([0-9]{1,2})\|(UNKNOWN|[0-9]{1,10})$'){Fail 'CRM_RESPONSE_NOT_ACCEPTED'}
 $count=[int]$Matches[1]
 $total=$Matches[2]
 if($count -gt 50 -or $count -lt 1){Fail 'FIELDS_PAGE_INVALID'}
 if($total -ne 'UNKNOWN' -and [int]$total -ne $count){Fail 'FIELDS_PARTIAL_PAGE'}
 $fieldsSql="SELECT 'OK|'||"+
  "sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_INN' THEN 1 ELSE 0 END)||'|'||"+
  "sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_KPP' THEN 1 ELSE 0 END)||'|'||"+
  "sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_OGRN' THEN 1 ELSE 0 END)||'|'||"+
  "sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_COMPANY_NAME' THEN 1 ELSE 0 END)||'|'||"+
  "sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_COMPANY_FULL_NAME' THEN 1 ELSE 0 END) "+
  "FROM j,json_each(j.doc,'$.result') AS e;"
 $fields=JsonSql $script:bodyReply $fieldsSql
 $script:bodyReply=$null
 if($fields -notmatch '^OK\|([01])\|([01])\|([01])\|([01])\|([01])$'){Fail 'FIELD_COUNTS_INVALID'}
 $inn=$Matches[1];$kpp=$Matches[2];$ogrn=$Matches[3];$name=$Matches[4];$fullname=$Matches[5]
 if($inn -ne '1' -or $name -ne '1'){Fail 'REQUIRED_FIELDS_MISSING'}
 $phase='WRITE_RECEIPT'
 $line='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;IDENTITY=LOCAL_SERVICE;TARGET=b24-uwmjda.bitrix24.ru;METHOD=crm.requisite.preset.field.list;PRESET_ID=1;FIELD_COUNT='+$count+';RQ_INN='+$inn+';RQ_KPP='+$kpp+';RQ_OGRN='+$ogrn+';RQ_COMPANY_NAME='+$name+';RQ_COMPANY_FULL_NAME='+$fullname+';CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=YES_ENCRYPTED'
 $file=New-Object IO.FileStream -ArgumentList @($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$bytes=[Text.Encoding]::ASCII.GetBytes($line);$file.Write($bytes,0,$bytes.Length);$file.Flush()}finally{$file.Close()}
 'LOCAL_SERVICE_API_READ=PASS'
 'IDENTITY=LOCAL_SERVICE'
 'PRESET_ID=1'
 'FIELD_COUNT='+$count
 'RQ_INN='+$inn
 'RQ_KPP='+$kpp
 'RQ_OGRN='+$ogrn
 'RQ_COMPANY_NAME='+$name
 'RQ_COMPANY_FULL_NAME='+$fullname
 'WEBHOOK_SOURCE=MACHINE_DPAPI'
 'WEBHOOK_SAVED=YES_ENCRYPTED'
 'CRM_WRITES=NO'
 'ONEC_CALLS=NO'
 'CUSTOMER_DATA_EXPORTED=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_LOCAL_SERVICE_API_READONLY'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^DIRECT_CRM_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{
  if(-not [IO.File]::Exists($receipt)){
   $failure='STATUS=FAIL;IDENTITY=LOCAL_SERVICE;GATE='+$gate+';PHASE='+$phase
   $stream=New-Object IO.FileStream -ArgumentList @($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
   try{$bytes=[Text.Encoding]::ASCII.GetBytes($failure);$stream.Write($bytes,0,$bytes.Length);$stream.Flush()}finally{$stream.Close()}
  }
 }catch{}
 'RESULT=FAIL;STAGE=SRV_BITRIX_LOCAL_SERVICE_API_READONLY;GATE='+$gate
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}finally{
 if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 $plain=$null
 $secure=$null
 $script:cfg=$null
 $script:bodyReply=$null
}
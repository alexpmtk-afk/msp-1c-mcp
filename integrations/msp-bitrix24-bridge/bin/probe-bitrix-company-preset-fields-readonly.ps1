#requires -version 2
# Manual, one-shot READ-ONLY Bitrix24 CRM company preset field capability probe on physical SRV.
# Paste an incoming webhook BASE URL at the hidden prompt. Never print/store the secret.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$receipt=Join-Path $root 'state\bitrix-direct-company-preset-fields-readonly-status.txt'
$plain=$null
$secure=$null
$ptr=[IntPtr]::Zero
$cfg=$null
$bodyReply=$null
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
 if([IO.File]::Exists($receipt)){Fail 'ALREADY_TESTED_DIAGNOSE_FIRST'}
 foreach($f in @('bin\curl.exe','bin\sqlite3.exe','config\curl-ca-bundle.crt','state\bitrix-direct-https-smoke-status.txt')){
  $file=Join-Path $root $f
  if(-not [IO.File]::Exists($file)){Fail 'PREREQUISITE_MISSING'}
  if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 $https=[IO.File]::ReadAllText((Join-Path $root 'state\bitrix-direct-https-smoke-status.txt'),[Text.Encoding]::ASCII).Trim()
 if($https -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;TARGET=b24-uwmjda.bitrix24.ru;TLS_VERIFY=PASS;HTTP_STATUS=[0-9]{3};CUSTOMERS=6433;INDEX=6433;WORKER_ENABLED=NO;REST_CALLS=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0$'){Fail 'HTTPS_NOT_ACCEPTED'}
 $presetReceipt=Join-Path $root 'state\bitrix-direct-requisite-preset-details-status.txt'
 if(-not [IO.File]::Exists($presetReceipt)){Fail 'PRESET_DETAILS_NOT_VERIFIED'}
 $verified=[IO.File]::ReadAllText($presetReceipt,[Text.Encoding]::ASCII).Trim()
 if($verified -notmatch ';STATUS=PASS;TARGET=b24-uwmjda.bitrix24.ru;METHOD=crm.requisite.preset.list;DETAILS_COUNT=3;CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=NO$'){Fail 'PRESET_DETAILS_NOT_VERIFIED'}
 foreach($f in @('config\bitrix-search-worker.ini','secrets\bitrix-search-worker.dpapi')){
  if([IO.File]::Exists((Join-Path $root $f))){Fail 'LEGACY_RELAY_WORKER_CONFIGURED'}
 }
 $secure=Read-Host -Prompt 'Enter Bitrix incoming webhook BASE URL (hidden; never share)' -AsSecureString
 if($null -eq $secure -or $secure.Length -lt 45 -or $secure.Length -gt 220){Fail 'WEBHOOK_FORMAT_INVALID'}
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
 $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
 [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
 $ptr=[IntPtr]::Zero
 if($plain -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/?$'){Fail 'WEBHOOK_HOST_OR_FORMAT_INVALID'}
 $url=$plain.TrimEnd('/')+'/crm.requisite.preset.field.list.json'
 $payload='{"preset":{"ID":1},"start":0}'
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
 $line='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;TARGET=b24-uwmjda.bitrix24.ru;METHOD=crm.requisite.preset.field.list;PRESET_ID=1;FIELD_COUNT='+$count+';RQ_INN='+$inn+';RQ_KPP='+$kpp+';RQ_OGRN='+$ogrn+';RQ_COMPANY_NAME='+$name+';RQ_COMPANY_FULL_NAME='+$fullname+';CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=NO'
 $file=New-Object IO.FileStream -ArgumentList @($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$bytes=[Text.Encoding]::ASCII.GetBytes($line);$file.Write($bytes,0,$bytes.Length);$file.Flush()}finally{$file.Close()}
 'DIRECT_BITRIX_COMPANY_PRESET_FIELDS=PASS'
 'PRESET_ID=1'
 'FIELD_COUNT='+$count
 'RQ_INN='+$inn
 'RQ_KPP='+$kpp
 'RQ_OGRN='+$ogrn
 'RQ_COMPANY_NAME='+$name
 'RQ_COMPANY_FULL_NAME='+$fullname
 'WEBHOOK_SAVED=NO'
 'CRM_WRITES=NO'
 'ONEC_CALLS=NO'
 'CUSTOMER_DATA_EXPORTED=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_COMPANY_PRESET_FIELDS_READONLY'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^DIRECT_CRM_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_COMPANY_PRESET_FIELDS_READONLY;GATE='+$gate
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}finally{
 if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 $plain=$null
 $secure=$null
 $script:cfg=$null
 $script:bodyReply=$null
}
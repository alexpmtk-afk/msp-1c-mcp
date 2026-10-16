#requires -version 2
# One manual CRM synthetic company add/get/delete/list backread on physical SRV.
# Never touches 1C/SQLite customer records and never persists the Bitrix webhook.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$receipt=Join-Path $root 'state\bitrix-synthetic-company-smoke.txt'
$phase='PRECHECK'
$secure=$null
$ptr=[IntPtr]::Zero
$base=$null
$tokenText=$null
$createdId=$null
$marker=''
function Fail([string]$Code){throw ('SYNTHETIC_'+$Code)}
function Quote([string]$Value){
 if($Value -match '[\x00-\x1f\x7f]'){Fail 'CONFIG_CONTROLS'}
 return ('"'+$Value.Replace('\','\\').Replace('"','\"')+'"')
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
 if(@('crm.item.add','crm.item.get','crm.item.delete','crm.item.list') -notcontains $Method){Fail 'UNAPPROVED_METHOD'}
 if($Body.Length -gt 512 -or $Body -match '[^\x20-\x7e]'){Fail 'BODY_NOT_ASCII'}
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
 $msg='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS='+$State+';MARKER='+$script:marker
 if($null -ne $script:createdId){$msg+=';CREATED_ID='+$script:createdId}
 [IO.File]::WriteAllText($script:receipt,$msg,[Text.Encoding]::ASCII)
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([IO.File]::Exists($receipt)){Fail 'PRIOR_RUN_DIAGNOSE_FIRST'}
 foreach($file in @('bin\curl.exe','bin\sqlite3.exe','config\curl-ca-bundle.crt','state\bitrix-direct-crm-readonly-status.txt','state\bitrix-direct-contact-readonly-status.txt','state\bitrix-direct-https-smoke-status.txt')){
  $f=Join-Path $root $file
  if(-not [IO.File]::Exists($f)){Fail 'PREREQUISITE_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_PREREQUISITE'}
 }
 foreach($f in @('config\bitrix-search-worker.ini','secrets\bitrix-search-worker.dpapi')){
  if([IO.File]::Exists((Join-Path $root $f))){Fail 'OLD_RELAY_CONFIG_PRESENT'}
 }
 $company=[IO.File]::ReadAllText((Join-Path $root 'state\bitrix-direct-crm-readonly-status.txt'),[Text.Encoding]::ASCII)
 $contact=[IO.File]::ReadAllText((Join-Path $root 'state\bitrix-direct-contact-readonly-status.txt'),[Text.Encoding]::ASCII)
 if($company -notmatch ';STATUS=PASS;TARGET=b24-uwmjda.bitrix24.ru;METHOD=crm.item.list;ENTITY=COMPANY;FIELDS=id;FIRST_PAGE_COUNT=0;TOTAL=0;CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=NO$'){Fail 'COMPANY_BASELINE_NOT_ZERO'}
 if($contact -notmatch ';STATUS=PASS;TARGET=b24-uwmjda.bitrix24.ru;METHOD=crm.item.list;ENTITY=CONTACT;FIELDS=id;FIRST_PAGE_COUNT=0;TOTAL=0;CRM_WRITES=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0;WEBHOOK_SAVED=NO$'){Fail 'CONTACT_BASELINE_NOT_ZERO'}
 $secure=Read-Host -Prompt 'Bitrix webhook BASE URL (hidden; never paste into chat)' -AsSecureString
 if($null -eq $secure -or $secure.Length -lt 45 -or $secure.Length -gt 220){Fail 'WEBHOOK_INVALID'}
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
 $tokenText=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
 [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr);$ptr=[IntPtr]::Zero
 if($tokenText -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/?$'){Fail 'WEBHOOK_HOST_INVALID'}
 $script:base=$tokenText.TrimEnd('/')+'/'
 $tokenText=$null
 $script:marker=[Guid]::NewGuid().ToString('N')
 $title='MSP_SYNTHETIC_TEST_'+$script:marker
 # Persist a synthetic-only trace before first write; the operator can find an orphan by marker.
 WriteState 'BEFORE_ADD'
 $phase='ADD'
 $add='{"entityTypeId":4,"fields":{"title":"'+$title+'","originatorId":"MSP_SYNTHETIC_PROBE","originId":"'+$script:marker+'","opened":"N"}}'
 $result=Http 'crm.item.add' $add
 $addSql="SELECT CASE WHEN json_valid(doc)=0 THEN 'INVALID' WHEN coalesce(json_type(doc,'$.result.item.id'),'')<>'integer' THEN 'INVALID' ELSE CAST(json_extract(doc,'$.result.item.id') AS TEXT) END FROM j;"
 $rawId=SqlJson $result $addSql
 $result=$null
 if($rawId -notmatch '^[1-9][0-9]{0,9}$'){Fail 'ADD_ID_INVALID'}
 $script:createdId=[long]$rawId
 if($script:createdId -gt 2147483647){Fail 'ADD_ID_TOO_LARGE'}
 WriteState 'CREATED'
 'SYNTHETIC_COMPANY_CREATED=YES'
 'SYNTHETIC_COMPANY_ID='+$script:createdId
 $phase='BACKREAD'
 $get=Http 'crm.item.get' ('{"entityTypeId":4,"id":'+$script:createdId+'}')
 $select="SELECT CASE WHEN json_valid(doc)=0 THEN 'INVALID' "+
  "WHEN coalesce(json_type(doc,'$.result.item.id'),'')<>'integer' "+
  "OR coalesce(json_type(doc,'$.result.item.title'),'')<>'text' THEN 'INVALID' "+
  "ELSE CAST(json_extract(doc,'$.result.item.id') AS TEXT)||'|'||"+
  "hex(CAST(json_extract(doc,'$.result.item.title') AS BLOB))||'|'||"+
  "hex(CAST(coalesce(json_extract(doc,'$.result.item.originatorId'),'') AS BLOB))||'|'||"+
  "hex(CAST(coalesce(json_extract(doc,'$.result.item.originId'),'') AS BLOB)) END FROM j;"
 $fields=(SqlJson $get $select).Split('|')
 $get=$null
 if($fields.Length -ne 4 -or $fields[0] -ne [string]$script:createdId){Fail 'BACKREAD_ID_MISMATCH'}
 if((Unhex $fields[1]) -cne $title){Fail 'BACKREAD_TITLE_MISMATCH'}
 $source=Unhex $fields[2]
 $origin=Unhex $fields[3]
 if($source.Length -gt 0 -and $source -cne 'MSP_SYNTHETIC_PROBE'){Fail 'BACKREAD_SOURCE_MISMATCH'}
 if($origin.Length -gt 0 -and $origin -cne $script:marker){Fail 'BACKREAD_ORIGIN_MISMATCH'}
 WriteState 'BACKREAD_VERIFIED'
 'SYNTHETIC_COMPANY_BACKREAD=PASS'
 $phase='DELETE'
 # The ONLY deletable ID is the one just created and verified with its unique synthetic title.
 $del=Http 'crm.item.delete' ('{"entityTypeId":4,"id":'+$script:createdId+'}')
 $delCheck="SELECT CASE WHEN json_valid(doc)=0 THEN 'INVALID' "+
  "WHEN coalesce(json_type(doc,'$.result'),'')='array' "+
  "AND json_array_length(doc,'$.result')=0 THEN 'OK' ELSE 'INVALID' END FROM j;"
 if((SqlJson $del $delCheck) -ne 'OK'){Fail 'DELETE_NOT_ACKNOWLEDGED'}
 $del=$null
 WriteState 'DELETE_ACKED'
 $phase='VERIFY_DELETION'
 $list=Http 'crm.item.list' ('{"entityTypeId":4,"filter":{"id":'+$script:createdId+'},"select":["id"],"start":0}')
 $check="SELECT CASE WHEN json_valid(doc)=0 THEN 'INVALID' "+
  "WHEN coalesce(json_type(doc,'$.result.items'),'')='array' "+
  "AND json_array_length(doc,'$.result.items')=0 THEN 'ABSENT' ELSE 'INVALID' END FROM j;"
 if((SqlJson $list $check) -ne 'ABSENT'){Fail 'DELETION_BACKREAD_UNCONFIRMED'}
 $list=$null
 WriteState 'PASS_REMOVED'
 'SYNTHETIC_COMPANY_DELETED=PASS'
 'SYNTHETIC_COMPANY_ABSENT_AFTER_DELETE=PASS'
 'ONEC_DATABASE_WRITES=NO'
 'REAL_CUSTOMERS_EXPORTED=NO'
 'WEBHOOK_SAVED=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_SYNTHETIC_COMPANY_CREATE_READ_DELETE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^SYNTHETIC_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($script:marker.Length -gt 0){
  try{WriteState ('FAIL_'+$gate)}catch{}
 }
 'RESULT=FAIL;STAGE=SRV_BITRIX_SYNTHETIC_COMPANY_CREATE_READ_DELETE;GATE='+$gate+';PHASE='+$phase
 if($null -ne $script:createdId){'SYNTHETIC_COMPANY_ID='+$script:createdId}
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}finally{
 if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 $secure=$null
 $tokenText=$null
 $script:base=$null
}
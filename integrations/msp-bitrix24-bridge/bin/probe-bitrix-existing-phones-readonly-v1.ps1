#requires -version 2
# Read-only CRM native phone schema pilot; one source phone buyer per 1C kind 3 and 4.
# Physical SRV only. No source phone values, buyer IDs, or Bitrix responses leave SRV.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root
$status=Join-Path $root 'state\bitrix-phone-existing-fields-probe-v1.status'
$phase='PRECHECK'
function Require([bool]$OK,[string]$Code){if(-not $OK){Fail $Code}}
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function SqlRead([string]$SQL){
 $db=Join-Path $root 'data\customers.db'
 $exe=Join-Path $root 'bin\sqlite3.exe'
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=$exe;$i.Arguments='-readonly -batch -bail "'+$db+'"'
 $i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'SQLITE_START'}
  $p.StandardInput.WriteLine($SQL);$p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0){Fail 'SQLITE_QUERY_FAILED'}
  if($out.Length -gt 2048){Fail 'SQL_RESULT_TOO_LARGE'}
  return $out
 }finally{$p.Close()}
}
function PhoneShape([string]$Reply,[int]$Index,[string]$Guid,[string]$Id){
 Require ($Guid -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') 'GUID_INVALID'
 Require ($Id -match '^[1-9][0-9]{0,9}$') 'CRM_ID_INVALID'
 Require ($Index -ge 0 -and $Index -le 1) 'BATCH_INDEX_INVALID'
 $path='$.result.result.k'+$Index+'.item.'
 $idPath="'"+$path+"id'"
 $originPath="'"+$path+"originId'"
 $ownerPath="'"+$path+"originatorId'"
 $fmPath="'"+$path+"fm'"
 $fm=(SqlJson $Reply ("SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID_JSON' WHEN json_type(doc,'"+$path.TrimEnd('.')+"')<>'object' THEN 'ITEM_MISSING' WHEN coalesce(CAST(json_extract(doc,"+$idPath+") AS TEXT),'')<>'"+$Id+"' THEN 'ID_MISMATCH' WHEN coalesce(CAST(json_extract(doc,"+$originPath+") AS TEXT),'')<>'"+$Guid+"' THEN 'SOURCE_ORIGIN_MISMATCH' WHEN coalesce(CAST(json_extract(doc,"+$ownerPath+") AS TEXT),'')<>'MSP_ONEC_NEWBASE' THEN 'SOURCE_OWNER_MISMATCH' WHEN json_type(doc,"+$fmPath+")='array' THEN 'ARRAY|'||(SELECT count(*) FROM json_each(doc,"+$fmPath+") WHERE upper(coalesce(json_extract(value,'$.typeId'),''))='PHONE' AND length(trim(coalesce(json_extract(value,'$.value'),'')))>0) WHEN json_type(doc,"+$fmPath+") IS NULL OR json_type(doc,"+$fmPath+")='null' THEN 'ABSENT|0' ELSE 'UNEXPECTED_FM_TYPE' END FROM j;"))
 Require ($fm -match '^(ARRAY|ABSENT)\|[0-9]{1,2}$') 'CRM_PHONE_SCHEMA_INVALID'
 $parts=$fm.Split('|')
 Require ([int]$parts[1] -le 10) 'PHONE_FIELD_COUNT_UNEXPECTED'
 return $fm
}
try{
 Require ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'HOST_NOT_SRV'
 Require ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Require ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_REQUIRED'
 Require (-not [IO.File]::Exists($status)) 'RECEIPT_ALREADY_EXISTS'
 $snap=Join-Path $root 'state\customer-phone-snapshot-v2.status'
 $phoneDB=Join-Path $root 'data\phone-source-newbase-v1.sqlite'
 $mainDB=Join-Path $root 'data\customers.db'
 foreach($file in @($snap,$phoneDB,$mainDB)){
  Require ([IO.File]::Exists($file)) 'SOURCE_MISSING'
  Require (([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 }
 $accepted=[IO.File]::ReadAllText($snap,[Text.Encoding]::ASCII).Trim()
 Require ($accepted -match '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;ACTIVE_BUYERS=6433;CONTACT_ROWS=10751;MATCHED_BUYER_ROWS=9975;OTHER_ROWS=776;PHONE_NUMBER_ROWS=4068;PHONE_WITHOUT_CODES_ROWS=3468;DISPLAY_ROWS=9973;PHONE_TYPE_ROWS=4068;PHONE_CANDIDATE_ROWS=4068;BUYERS_WITH_PHONE=4067;BUYERS_MULTIPLE_PHONES=1;PAGES=108;ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;STAGING_DB_WRITES=YES;PII_EXPORTED=0$') 'PHONE_SNAPSHOT_NOT_ACCEPTED'
 $phase='LOCAL_SQLITE_BACKREAD'
 Require ((SqlRead 'PRAGMA quick_check;') -eq 'ok') 'CUSTOMER_DB_NOT_OK'
 $phonePath='C:/ProgramData/MspCustomerStore/data/phone-source-newbase-v1.sqlite'
 $sql="ATTACH DATABASE '"+$phonePath+"' AS ph;SELECT count(*)||':'||count(DISTINCT onec_guid) FROM ph.phone_source;"
 Require ((SqlRead $sql) -eq '4068:4067') 'PHONE_DB_NOT_ACCEPTED'
 $phase='PICK_TWO_PILOT_CARD_TYPES'
 $sql="ATTACH DATABASE '"+$phonePath+"' AS ph;SELECT m.onec_guid||'|'||m.crm_id||'|'||m.entity_kind FROM msp_initial_map m JOIN customers c ON c.onec_guid=m.onec_guid JOIN ph.phone_source p ON p.onec_guid=m.onec_guid WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND m.entity_kind=3 AND m.crm_id>0 GROUP BY m.onec_guid HAVING count(*)=1 ORDER BY m.onec_guid LIMIT 1;"
 $contact=SqlRead $sql
 $sql="ATTACH DATABASE '"+$phonePath+"' AS ph;SELECT m.onec_guid||'|'||m.crm_id||'|'||m.entity_kind FROM msp_initial_map m JOIN customers c ON c.onec_guid=m.onec_guid JOIN ph.phone_source p ON p.onec_guid=m.onec_guid WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND m.entity_kind=4 AND m.crm_id>0 GROUP BY m.onec_guid HAVING count(*)=1 ORDER BY m.onec_guid LIMIT 1;"
 $company=SqlRead $sql
 $rows=@($contact,$company)
 Require ($rows.Count -eq 2 -and $contact.Length -gt 0 -and $company.Length -gt 0) 'PILOT_TYPES_MISSING'
 $cmd=New-Object Collections.ArrayList;$ids=New-Object Collections.ArrayList;$guids=New-Object Collections.ArrayList
 foreach($line in $rows){
  $v=$line.Split('|')
  Require ($v.Length -eq 3 -and $v[0] -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$' -and $v[1] -match '^[1-9][0-9]{0,9}$' -and @('3','4') -contains $v[2]) 'LOCAL_MAP_INVALID'
  [void]$ids.Add($v[1]);[void]$guids.Add($v[0])
  [void]$cmd.Add('crm.item.get?entityTypeId='+$v[2]+'&id='+$v[1])
 }
 $phase='CRM_READONLY_GET'
 Secret
 $reply=Batch @($cmd.ToArray())
 $phase='CRM_NATIVE_PHONE_FIELDS_VERIFY'
 $a=PhoneShape $reply 0 $guids[0] $ids[0]
 $b=PhoneShape $reply 1 $guids[1] $ids[1]
 $fields0=$a.Split('|');$fields1=$b.Split('|')
 $result='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;PILOT_CARDS=2;CRM_ORIGINS_VERIFIED=2;CONTACT_FM='+$fields0[0]+';CONTACT_PHONE_FIELDS='+$fields0[1]+';COMPANY_FM='+$fields1[0]+';COMPANY_PHONE_FIELDS='+$fields1[1]+';ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;PHONE_DB_WRITES=0;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$result,[Text.Encoding]::ASCII)
 $result
 'RESULT=PASS;STAGE=BITRIX_EXISTING_PHONE_FIELDS_READONLY_PILOT_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;SOURCE=TEST_NEWBASE;PHASE='+$phase+';GATE='+$gate+';PII_EXPORTED=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=BITRIX_EXISTING_PHONE_FIELDS_READONLY_PILOT_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}finally{$script:base=$null}

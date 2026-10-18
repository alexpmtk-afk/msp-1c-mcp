#requires -version 2
# Full read-only phone-presence audit of mapped TEST NewBase buyers with a saved phone.
# Physical SRV LOCAL SERVICE only. No CRM/source/customer/phone DB writes and no PII output.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root
$status=Join-Path $root 'state\bitrix-phone-presence-audit-v1.status'
$phase='PRECHECK';$script:crmReads=0
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$OK,[string]$Code){if(-not $OK){Fail $Code}}
function SqlRead([string]$SQL){
 $db=Join-Path $root 'data\customers.db'
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $root 'bin\sqlite3.exe'
 $i.Arguments='-readonly -batch -bail "'+$db+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'SQLITE_START'}
  $p.StandardInput.WriteLine($SQL);$p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $out.Length -gt 500000){Fail 'SQLITE_READ_FAILED'}
  return $out
 }finally{$p.Close()}
}
function FetchReadOnly([object[]]$Commands){
 Need ($Commands.Count -ge 1 -and $Commands.Count -le 20) 'BATCH_COUNT_INVALID'
 foreach($cmd in $Commands){Need ($cmd -match '^crm\.item\.get\?entityTypeId=[34]&id=[1-9][0-9]{0,9}$') 'NOT_READ_ONLY'}
 for($attempt=1;$attempt -le 3;$attempt++){
  try{return (Batch $Commands)}
  catch{
   $e=$_.Exception.Message
   $retry= @('NEWBASE_CURL_FAILED','NEWBASE_HTTP_429','NEWBASE_HTTP_503') -contains $e
   if(-not $retry -or $attempt -ge 3){throw}
   Start-Sleep -Seconds (3*$attempt)
  }
 }
 Fail 'BATCH_READ_EXHAUSTED'
}
function AuditBatch([string]$Reply,[object[]]$Records){
 Need ($Records.Count -ge 1 -and $Records.Count -le 20) 'BATCH_RECORD_COUNT'
 $pieces=New-Object Collections.ArrayList
 for($i=0;$i -lt $Records.Count;$i++){
  $v=$Records[$i]
  $guid=$v.guid;$id=$v.id
  Need ($guid -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$' -and $id -match '^[1-9][0-9]{0,9}$') 'EXPECTED_MAP_INVALID'
  $p='$.result.result.k'+$i+'.item'
  $ip="'"+$p+"'";$fm="'"+$p+".fm'"
  $ep="'$.result.result_error.k"+$i+"'"
  $sql="SELECT CASE WHEN json_type(doc,"+$ep+") IS NOT NULL THEN 'REST_ERROR' WHEN coalesce(json_type(doc,"+$ip+"),'missing')<>'object' THEN 'ITEM_NOT_OBJECT' WHEN coalesce(CAST(json_extract(doc,'"+$p+".id') AS TEXT),'')<>'"+$id+"' THEN 'ID_MISMATCH' WHEN coalesce(CAST(json_extract(doc,'"+$p+".originId') AS TEXT),'')<>'"+$guid+"' THEN 'ORIGIN_MISMATCH' WHEN coalesce(CAST(json_extract(doc,'"+$p+".originatorId') AS TEXT),'')<>'MSP_ONEC_NEWBASE' THEN 'ORIGINATOR_MISMATCH' WHEN coalesce(json_type(doc,"+$fm+"),'missing')<>'array' THEN 'FM_NOT_ARRAY' ELSE 'OK|'||(SELECT count(*) FROM json_each(doc,"+$fm+") WHERE upper(coalesce(json_extract(value,'$.typeId'),''))='PHONE' AND length(trim(coalesce(json_extract(value,'$.value'),'')))>0) END FROM j"
  [void]$pieces.Add($sql)
 }
 $results=SqlJson $Reply ([string]::Join(' UNION ALL ',[string[]]$pieces.ToArray()))
 $lines=@($results -split '\r?\n')
 Need ($lines.Count -eq $Records.Count) 'BATCH_RESULT_CARDINALITY'
 return ,$lines
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 Need (-not [IO.File]::Exists($status)) 'AUDIT_REPORT_ALREADY_EXISTS'
 $receipt=Join-Path $root 'state\customer-phone-snapshot-v2.status'
 $pilot=Join-Path $root 'state\bitrix-phone-existing-fields-probe-v1.status'
 $phdb=Join-Path $root 'data\phone-source-newbase-v1.sqlite'
 foreach($path in @($receipt,$pilot,$phdb,(Join-Path $root 'data\customers.db'))){
  Need ([IO.File]::Exists($path)) 'SOURCE_FILE_MISSING'
  Need (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 }
 $a=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 Need ($a -match '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;ACTIVE_BUYERS=6433;CONTACT_ROWS=10751;MATCHED_BUYER_ROWS=9975;OTHER_ROWS=776;PHONE_NUMBER_ROWS=4068;PHONE_WITHOUT_CODES_ROWS=3468;DISPLAY_ROWS=9973;PHONE_TYPE_ROWS=4068;PHONE_CANDIDATE_ROWS=4068;BUYERS_WITH_PHONE=4067;BUYERS_MULTIPLE_PHONES=1;PAGES=108;ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;STAGING_DB_WRITES=YES;PII_EXPORTED=0$') 'SNAPSHOT_NOT_ACCEPTED'
 $b=[IO.File]::ReadAllText($pilot,[Text.Encoding]::ASCII).Trim()
 Need ($b -match '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;PILOT_CARDS=2;CRM_ORIGINS_VERIFIED=2;CONTACT_FM=ARRAY;CONTACT_PHONE_FIELDS=0;COMPANY_FM=ARRAY;COMPANY_PHONE_FIELDS=0;ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;PHONE_DB_WRITES=0;PII_EXPORTED=0$') 'CRM_PILOT_NOT_ACCEPTED'
 $phase='VERIFY_LOCAL_SOURCE'
 Need ((SqlRead 'PRAGMA quick_check;') -eq 'ok') 'MAIN_DB_CORRUPT'
 $ph="ATTACH DATABASE 'C:/ProgramData/MspCustomerStore/data/phone-source-newbase-v1.sqlite' AS ph;"
 $phoneStats=SqlRead ($ph+"SELECT count(*)||':'||count(DISTINCT onec_guid) FROM ph.phone_source;PRAGMA quick_check;")
 Need ($phoneStats -match '^4068:4067(?:\r?\n)ok$') 'PHONE_DB_INVALID'
 $sql=$ph+"SELECT m.onec_guid||'|'||m.crm_id||'|'||m.entity_kind||'|'||count(p.line_number) FROM ph.phone_source p JOIN customers c ON c.onec_guid=p.onec_guid JOIN msp_initial_map m ON m.onec_guid=p.onec_guid WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 GROUP BY m.onec_guid,m.crm_id,m.entity_kind ORDER BY m.onec_guid;"
 $raw=SqlRead $sql
 $lines=@($raw -split '\r?\n')
 Need ($lines.Count -eq 4067) 'MAPPED_PHONE_BUYERS_NOT_4067'
 $records=New-Object Collections.ArrayList
 $sumPhones=0;$multiple=0;$seenIds=@{}
 foreach($line in $lines){
  $v=$line.Split('|')
  Need ($v.Count -eq 4) 'ROW_SHAPE_INVALID'
  Need ($v[0] -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[0-9a-f]{12}$' -and $v[1] -match '^[1-9][0-9]{0,9}$' -and @('3','4') -contains $v[2] -and @('1','2') -contains $v[3]) 'LOCAL_MAP_INVALID'
  $key=$v[2]+':'+$v[1]
  Need (-not $seenIds.ContainsKey($key)) 'CRM_CARD_DUPLICATE'
  $seenIds[$key]=$true
  $sumPhones+=[int]$v[3]
  if($v[3] -eq '2'){$multiple++}
  [void]$records.Add((New-Object PSObject -Property @{guid=$v[0];id=$v[1];type=$v[2]}))
 }
 Need ($sumPhones -eq 4068 -and $multiple -eq 1) 'PHONE_ROWS_COUNT_MISMATCH'
 $phase='READ_ALL_MAPPED_CRM_CARDS'
 Secret
 $checked=0;$noPhone=0;$hasPhone=0;$multiPhone=0;$crmPhoneFields=0;$batchCount=0
 while($checked -lt $records.Count){
  $items=New-Object Collections.ArrayList
  $cmds=New-Object Collections.ArrayList
  for($j=$checked;$j -lt $records.Count -and $j -lt ($checked+20);$j++){
   $r=$records[$j]
   [void]$items.Add($r)
   [void]$cmds.Add('crm.item.get?entityTypeId='+$r.type+'&id='+$r.id)
  }
  $reply=FetchReadOnly @($cmds.ToArray())
  $script:crmReads+=$cmds.Count
  $statuses=AuditBatch $reply @($items.ToArray())
  foreach($state in $statuses){
   Need ($state -match '^OK\|([0-9]{1,2})$') 'CRM_ORIGIN_OR_FM_INVALID'
   $count=[int]$Matches[1]
   Need ($count -le 20) 'EXCESSIVE_CRM_PHONE_FIELDS'
   if($count -eq 0){$noPhone++}else{$hasPhone++}
   if($count -gt 1){$multiPhone++}
   $crmPhoneFields+=$count
  }
  $checked+=$items.Count;$batchCount++
  if(($batchCount % 10) -eq 0){[IO.File]::WriteAllText($status,('STATUS=RUNNING;SOURCE=TEST_NEWBASE;CHECKED='+$checked+';TOTAL=4067;CRM_WRITES=0;PII_EXPORTED=0'),[Text.Encoding]::ASCII)}
  Start-Sleep -Milliseconds 500
 }
 Need ($checked -eq 4067 -and ($noPhone+$hasPhone) -eq 4067) 'AUDIT_COUNT_MISMATCH'
 $phase='WRITE_AGGREGATE_RECEIPT'
 $msg='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;BUYERS_WITH_SOURCE_PHONE=4067;SOURCE_PHONE_ROWS=4068;CRM_CARDS_VERIFIED='+$checked+';CRM_PHONE_EMPTY='+$noPhone+';CRM_PHONE_PRESENT='+$hasPhone+';CRM_MULTIPLE_PHONE_CARDS='+$multiPhone+';CRM_PHONE_FIELDS='+$crmPhoneFields+';BATCHES='+$batchCount+';ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;PHONE_DB_WRITES=0;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$msg,[Text.Encoding]::ASCII)
 $msg
 'RESULT=PASS;STAGE=BITRIX_PHONE_PRESENCE_FULL_READONLY_AUDIT_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;SOURCE=TEST_NEWBASE;PHASE='+$phase+';GATE='+$gate+';CRM_READS_ATTEMPTED='+$script:crmReads+';ONEC_WRITES=0;CRM_WRITES=0;PII_EXPORTED=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=BITRIX_PHONE_PRESENCE_FULL_READONLY_AUDIT_V1;PHASE='+$phase+';GATE='+$gate+';CRM_READS_ATTEMPTED='+$script:crmReads
 exit 1
}finally{$script:base=$null}

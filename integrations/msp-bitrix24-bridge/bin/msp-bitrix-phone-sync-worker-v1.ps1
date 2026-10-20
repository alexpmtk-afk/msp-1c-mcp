#requires -version 2
# Guarded TEST NewBase -> mapped existing Bitrix CRM phone sync. PS2/CLR2, physical SRV LOCAL SERVICE.
# Pilot: exactly one company. Batch: max 20 per invocation, only after independently accepted pilot.
# Never repeat uncertain POST; every item is INTENT before writing and DONE only after verified GET.
param([string]$ExpectedComputerName='SRV',[ValidateSet('Pilot','Batch')][string]$Mode='Pilot',[int]$MaxCards=1)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root
$phase='PRECHECK';$posted=0;$verified=0;$intent=0;$lock=$null;$locked=$false
$status=Join-Path $root ('state\msp-bitrix-phone-sync-'+$Mode.ToLowerInvariant()+'-v1.status')
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Condition,[string]$Gate){if(-not $Condition){Fail $Gate}}
function Inspect([string]$Response,[int]$Index,[string]$Guid,[string]$CrmId,[string]$Kind){
 $p='$.result.result.k'+$Index+'.item';$j="'"+$p+"'"
 $e="'$.result.result_error.k"+$Index+"'"
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'JSON_INVALID' WHEN json_type(doc,"+$e+") IS NOT NULL THEN 'CRM_ERROR' WHEN coalesce(json_type(doc,"+$j+"),'missing')<>'object' THEN 'ITEM_MISSING' WHEN coalesce(CAST(json_extract(doc,'"+$p+".id') AS TEXT),'')<>'"+$CrmId+"' THEN 'ID_MISMATCH' WHEN coalesce(CAST(json_extract(doc,'"+$p+".originId') AS TEXT),'')<>'"+$Guid+"' THEN 'ORIGIN_MISMATCH' WHEN coalesce(CAST(json_extract(doc,'"+$p+".originatorId') AS TEXT),'')<>'MSP_ONEC_NEWBASE' THEN 'ORIGINATOR_MISMATCH' WHEN coalesce(json_type(doc,'"+$p+".fm'),'missing')<>'array' THEN 'FM_MISSING' ELSE 'PASS' END FROM j;"
 return (SqlJson $Response $sql)
}
function PhoneCount([string]$Response,[int]$Index,[string[]]$Expected){
 $p="'$.result.result.k"+$Index+".item.fm'"
 $sql="SELECT count(*) FROM j,json_each(doc,"+$p+") WHERE upper(coalesce(json_extract(value,'$.typeId'),''))='PHONE';"
 $n=SqlJson $Response $sql
 Need ($n -match '^[0-9]{1,3}$') 'PHONE_COUNT_INVALID'
 $match=0
 foreach($x in $Expected){
  $h=HexUtf8 $x
  $q="SELECT count(*) FROM j,json_each(doc,"+$p+") WHERE upper(coalesce(json_extract(value,'$.typeId'),''))='PHONE' AND hex(CAST(json_extract(value,'$.value') AS BLOB))='"+$h+"';"
  $v=SqlJson $Response $q
  Need ($v -match '^[0-9]{1,3}$') 'PHONE_VALUE_INVALID'
  $match+=[int]$v
 }
 return (([int]$n).ToString()+':'+$match)
}
function OtherFM([string]$Response,[int]$Index){
 $p="'$.result.result.k"+$Index+".item.fm'"
 $s="SELECT hex(CAST(coalesce((SELECT group_concat(row,'~') FROM (SELECT coalesce(json_extract(value,'$.id'),'')||':'||upper(coalesce(json_extract(value,'$.typeId'),''))||':'||coalesce(json_extract(value,'$.valueType'),'')||':'||hex(CAST(coalesce(json_extract(value,'$.value'),'') AS BLOB)) AS row FROM j,json_each(doc,"+$p+") WHERE upper(coalesce(json_extract(value,'$.typeId'),''))<>'PHONE' ORDER BY coalesce(json_extract(value,'$.id'),''))), '') AS BLOB)) FROM j;"
 return (SqlJson $Response $s)
}
function GetCards([object[]]$Items){
 $cmds=New-Object Collections.ArrayList
 foreach($it in $Items){[void]$cmds.Add('crm.item.get?entityTypeId='+$it.kind+'&id='+$it.id)}
 # Read-only HTTP failure may be retried; write batches never are.
 for($t=1;$t -le 3;$t++){
  try{return (Batch @($cmds.ToArray()))}
  catch{
   if(@('NEWBASE_CURL_FAILED','NEWBASE_HTTP_429','NEWBASE_HTTP_503') -notcontains $_.Exception.Message -or $t -eq 3){throw}
   Start-Sleep -Seconds (2*$t)
  }
 }
 Fail 'READ_RETRY_EXHAUSTED'
}
function CandidateRows(){
 $suffix=if($Mode -eq 'Pilot'){"AND q.entity_kind=4 AND q.phone_count=1"}else{''}
 $sql="SELECT q.onec_guid||'|'||q.crm_id||'|'||q.entity_kind||'|'||(SELECT group_concat(h,';') FROM (SELECT hex(CAST(phone_number AS BLOB)) AS h FROM msp_customer_phone p WHERE p.onec_guid=q.onec_guid AND p.format_review=0 ORDER BY p.line_number)) FROM msp_bitrix_phone_queue q JOIN msp_initial_map m ON m.onec_guid=q.onec_guid AND m.crm_id=q.crm_id AND m.entity_kind=q.entity_kind JOIN customers c ON c.onec_guid=q.onec_guid WHERE q.state='PENDING' AND c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 "+$suffix+" AND q.phone_count=(SELECT count(*) FROM msp_customer_phone p WHERE p.onec_guid=q.onec_guid AND p.format_review=0) ORDER BY q.onec_guid LIMIT "+$MaxCards+";"
 return (Query $sql)
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'HOST_INVALID'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 Need (($Mode -eq 'Pilot' -and $MaxCards -eq 1) -or ($Mode -eq 'Batch' -and $MaxCards -ge 1 -and $MaxCards -le 20)) 'CARD_BOUNDS_INVALID'
 Need (-not [IO.File]::Exists($status) -or $Mode -eq 'Batch') 'PILOT_ALREADY_ATTEMPTED'
 $lock=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspBitrixPhoneQueueWriterV1')
 Need ($lock.WaitOne(0,$false)) 'ANOTHER_PHONE_WRITER_RUNNING';$locked=$true
 $receipt=Join-Path $root 'state\msp-bitrix-phone-queue-v1.status'
 Need ([IO.File]::Exists($receipt)) 'QUEUE_NOT_PREPARED'
 $a=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 Need ($a -match 'STATUS=PASS;SOURCE=TEST_NEWBASE;QUEUE_BUYERS=4031;QUEUE_PHONE_ROWS=4032;COMPANY_SINGLE=1089;CONTACT_SINGLE=2941;TWO_PHONE_BUYERS=1;REVIEW_EXCLUDED=36;BACKUP=VERIFIED;SQLITE_QUICK_CHECK=OK;CRM_WRITES=0') 'QUEUE_RECEIPT_NOT_ACCEPTED'
 if($Mode -eq 'Batch'){
  $pilot=Join-Path $root 'state\msp-bitrix-phone-sync-pilot-v1.status'
  Need ([IO.File]::Exists($pilot)) 'PILOT_REQUIRED'
  Need ([IO.File]::ReadAllText($pilot,[Text.Encoding]::ASCII) -match 'STATUS=PASS;MODE=Pilot;POST_BATCHES=1;VERIFIED=1;CRM_WRITES=1;BACKREAD=PASS') 'PILOT_NOT_ACCEPTED'
  # Batch execution is manual only; never installed on a repeating schedule.
 }
 $phase='SELECT'
 Need ((Query 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_INTEGRITY'
 $raw=CandidateRows
 Need ($raw.Length -gt 0 -and $raw.Length -lt 8000) 'NO_ELIGIBLE_PENDING'
 $items=New-Object Collections.ArrayList
 foreach($line in ($raw -split '\r?\n')){
  $v=$line.Split('|')
  Need ($v.Length -eq 4 -and $v[0] -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$' -and $v[1] -match '^[1-9][0-9]{0,9}$' -and @('3','4') -contains $v[2]) 'QUEUE_ROW_INVALID'
  $nums=New-Object Collections.ArrayList
  foreach($h in $v[3].Split(';')){
   Need ($h -match '^(?:[0-9A-F]{2}){7,40}$') 'PHONE_HEX_INVALID'
   $phone=Unhex $h
   Need ($phone -match '^[0-9+() ./-]{7,40}$') 'PHONE_CHAR_INVALID'
   [void]$nums.Add($phone)
  }
  Need ($nums.Count -ge 1 -and $nums.Count -le 2) 'PHONE_COUNT_INVALID'
  [void]$items.Add((New-Object PSObject -Property @{guid=$v[0];id=$v[1];kind=$v[2];numbers=@($nums.ToArray());other=''}))
 }
 Need ($items.Count -ge 1 -and $items.Count -le $MaxCards) 'SELECT_COUNT_INVALID'
 $phase='CRM_PREFLIGHT'
 Secret
 $before=GetCards @($items.ToArray())
 for($i=0;$i -lt $items.Count;$i++){
  $it=$items[$i]
  Need ((Inspect $before $i $it.guid $it.id $it.kind) -eq 'PASS') 'CRM_ORIGIN_INVALID'
  Need ((PhoneCount $before $i $it.numbers) -eq '0:0') 'CRM_PHONE_ALREADY_PRESENT'
  $it.other=OtherFM $before $i
 }
 $phase='PERSIST_INTENT'
 $sql='BEGIN IMMEDIATE;'
 foreach($it in $items){
  $sql+="UPDATE msp_bitrix_phone_queue SET state='INTENT',updated_utc=datetime('now') WHERE onec_guid='"+$it.guid+"' AND crm_id="+$it.id+" AND entity_kind="+$it.kind+" AND state='PENDING';"
  $sql+="CREATE TEMP TABLE IF NOT EXISTS _expected_changes(n INTEGER CHECK(n=1));INSERT INTO _expected_changes VALUES (changes());DELETE FROM _expected_changes;"
 }
 $sql+='COMMIT;'
 $null=Query $sql;$intent=$items.Count
 $phase='CRM_UPDATE_ONCE'
 $commands=New-Object Collections.ArrayList
 foreach($it in $items){
  $cmd='crm.item.update?entityTypeId='+$it.kind+'&id='+$it.id
  for($j=0;$j -lt $it.numbers.Count;$j++){
   $key='n'+$j
   $cmd+='&fields[fm]['+$key+'][typeId]=PHONE&fields[fm]['+$key+'][valueType]=OTHER&fields[fm]['+$key+'][value]='+(Url $it.numbers[$j])
  }
  Need ($cmd -match '^crm\.item\.update\?entityTypeId=[34]&id=[1-9][0-9]{0,9}&fields\[fm\]\[n0\]\[typeId\]=PHONE') 'UPDATE_METHOD_UNAPPROVED'
  [void]$commands.Add($cmd)
 }
 $posted=1
 $writeReply=Batch @($commands.ToArray())  # NEVER RETRY, including 429/5xx/timeouts.
 $phase='CRM_BACKREAD'
 $after=GetCards @($items.ToArray())
 for($i=0;$i -lt $items.Count;$i++){
  $it=$items[$i]
  Need ((Inspect $after $i $it.guid $it.id $it.kind) -eq 'PASS') 'BACKREAD_IDENTITY_FAILED'
  Need ((PhoneCount $after $i $it.numbers) -eq ($it.numbers.Count.ToString()+':'+$it.numbers.Count)) 'BACKREAD_PHONE_FAILED'
  Need ((OtherFM $after $i) -eq $it.other) 'BACKREAD_NONPHONE_FIELDS_CHANGED'
  $null=Query ("UPDATE msp_bitrix_phone_queue SET state='DONE',updated_utc=datetime('now'),verified_utc=datetime('now') WHERE onec_guid='"+$it.guid+"' AND crm_id="+$it.id+" AND state='INTENT';SELECT changes();")
  $verified++
 }
 $phase='FINAL'
 $proof='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;MODE='+$Mode+';POST_BATCHES=1;VERIFIED='+$verified+';CRM_WRITES='+$items.Count+';BACKREAD=PASS;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$proof,[Text.Encoding]::ASCII)
 $proof
 'RESULT=PASS;STAGE=MSP_BITRIX_PHONE_SYNC_'+$Mode.ToUpperInvariant()+'_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($intent -gt 0){
  # Mark intent rows UNCERTAIN, not pending. Never retry POST without a separate read-only reconciliation.
  try{foreach($it in $items){$null=Query ("UPDATE msp_bitrix_phone_queue SET state='UNCERTAIN',updated_utc=datetime('now') WHERE onec_guid='"+$it.guid+"' AND state='INTENT';")}}catch{}
 }
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';POST_BATCHES_ATTEMPTED='+$posted+';VERIFIED='+$verified+';UNVERIFIED='+($intent-$verified)+';AUTO_UPDATE=OFF;PII_EXPORTED=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=MSP_BITRIX_PHONE_SYNC_'+$Mode.ToUpperInvariant()+'_V1;PHASE='+$phase+';GATE='+$gate+';POST_BATCHES_ATTEMPTED='+$posted
 exit 1
}finally{
 if($locked){$lock.ReleaseMutex()}
 if($null -ne $lock){$lock.Close()}
 $script:base=$null;$before=$null;$after=$null;$writeReply=$null;$raw=$null
}

#requires -version 2
# DAILY TEST NewBase: update one already mapped CRM buyer per run, not deletion.
# Default read-only; -Apply requires separate CRM approval; phones/emails preserved.
# Default: read-only. CRM mutation needs -Apply and separate local approval.
param([string]$ExpectedComputerName='SRV',[string]$OnecGuid='',[switch]$Apply)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root;$phase='PRECHECK'
$script:writes=0;$intent=$false;$guid=''
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function MatchJson([string]$Response,[string]$Path,[string]$Expected){
 if($Path -notmatch '^\$\.result\.result\.k0\.(item\.(id|originatorId|originId|title|name|lastName|secondName)|(ID|ENTITY_ID|ENTITY_TYPE_ID|PRESET_ID|NAME|RQ_COMPANY_NAME|RQ_COMPANY_FULL_NAME|RQ_INN))$'){Fail 'JSON_PATH_REJECTED'}
 $hex=HexUtf8 $Expected
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN hex(CAST(coalesce(json_extract(doc,'"+$Path+"'),'') AS BLOB))='"+$hex+"' THEN 'MATCH' ELSE 'DIFF' END FROM j;"
 return (SqlJson $Response $sql)
}
function GetSingle([string]$Response,[string]$Path,[string]$IdField){
 if(@('$.result.result.k0.items','$.result.result.k0') -notcontains $Path){Fail 'LIST_PATH_INVALID'}
 if(@('id','ID') -notcontains $IdField){Fail 'ID_FIELD_INVALID'}
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN json_type(doc,'"+$Path+"')<>'array' THEN 'INVALID' WHEN json_array_length(doc,'"+$Path+"')<>1 THEN 'NOT_SINGLE' WHEN coalesce(json_type(doc,'$.result.result_next.k0'),'null')<>'null' THEN 'PAGED' ELSE CAST(json_extract(doc,'"+$Path+"[0]."+$IdField+"') AS TEXT) END FROM j;"
 return (SqlJson $Response $sql)
}
function Stable([string]$Guid,[string]$Stamp){
 $q="SELECT count(*) FROM msp_daily_queue o JOIN customers c ON c.onec_guid=o.onec_guid WHERE o.onec_guid='"+$Guid+"' AND o.kind='UPDATE' AND o.state IN ('PENDING','INTENT') AND o.source_utc="+(Lit $Stamp)+" AND c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND c.needs_review=0;"
 return ((Query $q) -eq '1')
}
function ReadItem([int]$Type,[int]$Id,[string]$Guid,[string]$Name){
 $r=Batch @('crm.item.get?entityTypeId='+$Type+'&id='+$Id)
 Need ((MatchJson $r '$.result.result.k0.item.id' ([string]$Id)) -eq 'MATCH') 'ITEM_ID_MISMATCH'
 Need ((MatchJson $r '$.result.result.k0.item.originatorId' 'MSP_ONEC_NEWBASE') -eq 'MATCH') 'ORIGINATOR_MISMATCH'
 Need ((MatchJson $r '$.result.result.k0.item.originId' $Guid) -eq 'MATCH') 'ORIGIN_GUID_MISMATCH'
 $field=if($Type -eq 4){'title'}else{'name'}
 if($Type -eq 3){
  Need ((MatchJson $r '$.result.result.k0.item.lastName' '') -eq 'MATCH') 'SPLIT_CONTACT_UNSUPPORTED'
  Need ((MatchJson $r '$.result.result.k0.item.secondName' '') -eq 'MATCH') 'SPLIT_CONTACT_UNSUPPORTED'
 }
 return (MatchJson $r ('$.result.result.k0.item.'+$field) $Name)
}
function ReadRequisite([int]$ReqId,[int]$CrmId,[string]$Name,[string]$Full,[string]$Inn){
 $r=Batch @('crm.requisite.get?id='+$ReqId)
 foreach($pair in @(@('ID',[string]$ReqId),@('ENTITY_ID',[string]$CrmId),@('ENTITY_TYPE_ID','4'),@('PRESET_ID','1'))){
  Need ((MatchJson $r ('$.result.result.k0.'+$pair[0]) ([string]$pair[1])) -eq 'MATCH') 'REQUISITE_OWNER_MISMATCH'
 }
 $all=$true
 foreach($pair in @(@('NAME',$Name),@('RQ_COMPANY_NAME',$Name),@('RQ_COMPANY_FULL_NAME',$Full),@('RQ_INN',$Inn))){
  if((MatchJson $r ('$.result.result.k0.'+$pair[0]) ([string]$pair[1])) -ne 'MATCH'){$all=$false}
 }
 return $all
}
function Done([string]$Guid,[string]$Stamp,[int]$Id,[int]$Type){
 $sql="BEGIN IMMEDIATE;UPDATE msp_daily_queue SET state='DONE' WHERE onec_guid='"+$Guid+"' AND kind='UPDATE' AND state='INTENT' AND source_utc="+(Lit $Stamp)+" AND crm_id="+$Id+" AND entity_kind="+$Type+";CREATE TEMP TABLE _ack(n INTEGER NOT NULL CHECK(n=1));INSERT INTO _ack SELECT changes();DELETE FROM msp_auto_ops WHERE onec_guid='"+$Guid+"' AND operation='DAILY_UPDATE_SENT' AND crm_id="+$Id+";COMMIT;"
 $null=Query $sql
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 if($OnecGuid -ne ''){Need ($OnecGuid -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') 'GUID_INVALID'}
 $table=Query "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='msp_daily_queue';"
 Need (@('0','1') -contains $table) 'DAILY_QUEUE_SCHEMA_INVALID'
 if($table -eq '0'){'QUEUE_PENDING=0';'CRM_WRITES=0';'RESULT=PASS;STAGE=MSP_DAILY_CRM_IDLE_V1';exit 0}
 $bad=Query "SELECT coalesce(sum(state IN ('INTENT','UNCERTAIN')),0) FROM msp_daily_queue;"
 Need ($bad -eq '0') 'PRIOR_AMBIGUITY'
 if($OnecGuid -eq ''){$OnecGuid=Query "SELECT onec_guid FROM msp_daily_queue WHERE kind='UPDATE' AND state='PENDING' ORDER BY source_utc,onec_guid LIMIT 1;"}
 if($OnecGuid -eq ''){'QUEUE_PENDING=0';'CRM_WRITES=0';'RESULT=PASS;STAGE=MSP_DAILY_CRM_IDLE_V1';exit 0}
 Need ($OnecGuid -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') 'QUEUE_GUID_INVALID'
 $guid=$OnecGuid
 $receipt=Join-Path $root 'state\msp-newbase-daily-0745-v1.status'
 Need ([IO.File]::Exists($receipt)) 'SOURCE_RECEIPT_MISSING'
 Need ([IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII) -match 'STATUS=PASS;SOURCE=TEST_NEWBASE') 'SOURCE_NOT_TEST_NEWBASE'
 $mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspNewbaseBitrixUpdateOnceV1')
 $locked=$false
 if(-not $mutex.WaitOne(0,$false)){Fail 'WORKER_BUSY'};$locked=$true
 try{
  $phase='LOAD_LOCAL_PENDING'
  $q="SELECT c.onec_type||'|'||hex(CAST(coalesce(nullif(trim(c.name_short),''),trim(c.name_full),'') AS BLOB))||'|'||hex(CAST(coalesce(trim(c.name_full),'') AS BLOB))||'|'||hex(CAST(coalesce(nullif(trim(c.person_name),''),trim(c.name_short),'') AS BLOB))||'|'||hex(CAST(coalesce(trim(c.inn),'') AS BLOB))||'|'||hex(CAST(o.source_utc AS BLOB)) FROM msp_daily_queue o JOIN customers c ON c.onec_guid=o.onec_guid WHERE o.onec_guid='"+$OnecGuid+"' AND o.kind='UPDATE' AND o.state='PENDING' AND o.crm_id>0 AND o.entity_kind IN (3,4) AND c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND c.needs_review=0 AND c.onec_type IN ('LEGAL','PERSON') LIMIT 2;"
  $line=Query $q
  Need ($line -ne '' -and $line.IndexOf([char]10) -lt 0) 'PENDING_ROW_NOT_SINGLE'
  $v=$line.Split('|');Need ($v.Length -eq 6) 'LOCAL_ROW_INVALID'
  $category=$v[0];$name=Unhex $v[1];$full=Unhex $v[2];$person=Unhex $v[3];$inn=Unhex $v[4];$stamp=Unhex $v[5]
  Need ($stamp -match '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{7})?Z$') 'STAMP_INVALID'
  $kind=if($category -eq 'LEGAL'){4}else{3}
  if($kind -eq 4){
   Need ($name.Trim().Length -ge 2 -and $name.Length -le 160) 'LEGAL_NAME_INVALID'
   Need ($full.Trim().Length -ge 2 -and $full.Length -le 256) 'LEGAL_FULL_NAME_INVALID'
   Need ($inn -match '^(?:[0-9]{10}|[0-9]{12})$') 'LEGAL_INN_MISSING_OR_INVALID'
   $wanted=$name
  }else{
   Need ($person.Trim().Length -ge 2 -and $person.Length -le 160) 'CONTACT_NAME_INVALID'
   $wanted=$person
  }
  $hasOps=Query "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='msp_auto_ops';"
  if($hasOps -eq '1'){Need ((Query ("SELECT count(*) FROM msp_auto_ops WHERE onec_guid='"+$OnecGuid+"';")) -eq '0') 'PRIOR_CRM_WRITE_UNCERTAIN'}
  $phase='CRM_ORIGIN_SEARCH'
  Secret
  $r=Batch @('crm.item.list?entityTypeId='+$kind+'&filter[originatorId]=MSP_ONEC_NEWBASE&filter[originId]='+$OnecGuid+'&select[0]=id&start=0')
  $id=GetSingle $r '$.result.result.k0.items' 'id'
  Need ($id -match '^[1-9][0-9]{0,9}$') 'ORIGIN_NOT_SINGLE'
  $id=[int]$id
  Need ((Query ("SELECT count(*) FROM msp_daily_queue WHERE onec_guid='"+$OnecGuid+"' AND crm_id="+$id+" AND entity_kind="+$kind+" AND state='PENDING';")) -eq '1') 'CRM_MAP_MISMATCH'
   $phase='CRM_ITEM_READ'
  $itemState=ReadItem $kind $id $OnecGuid $wanted
  Need (@('MATCH','DIFF') -contains $itemState) 'CRM_ITEM_INVALID'
  $reqId=0;$reqMatch=$true
  if($kind -eq 4){
   $phase='CRM_REQUISITE_LIST'
   $r=Batch @('crm.requisite.list?filter[ENTITY_TYPE_ID]=4&filter[ENTITY_ID]='+$id+'&select[0]=ID&select[1]=ENTITY_ID&select[2]=ENTITY_TYPE_ID&select[3]=PRESET_ID&start=0')
   $reqId=GetSingle $r '$.result.result.k0' 'ID'
   Need ($reqId -match '^[1-9][0-9]{0,9}$') 'REQUISITE_NOT_SINGLE'
   $reqId=[int]$reqId
   $phase='CRM_REQUISITE_READ'
   $reqMatch=ReadRequisite $reqId $id $name $full $inn
  }
  Need (Stable $OnecGuid $stamp) 'SOURCE_CHANGED'
  'SOURCE=TEST_NEWBASE'
  'ORIGIN_VERIFIED=YES'
  'ITEM_STATUS='+$itemState
  'REQUISITE_STATUS='+$(if($kind -eq 3){'NOT_APPLICABLE'}elseif($reqMatch){'MATCH'}else{'DIFF'})
  'SOURCE_GENERATION='+$stamp
  if(-not $Apply){
   'CRM_WRITES=0'
   'LOCAL_WRITES=0'
   'RESULT=PASS;STAGE=MSP_DAILY_CRM_DRYRUN_V1'
   exit 0
  }
  $phase='CHECK_EXPLICIT_APPROVAL'
  $approval=Join-Path $root 'config\daily-newbase-crm-approval.txt'
  Need ([IO.File]::Exists($approval)) 'APPROVAL_FILE_MISSING'
  Need (([IO.File]::GetAttributes($approval) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'APPROVAL_REPARSE_DENIED'
  # Daily update opt-in: explicit and distinct from new-buyer auto create.
   Need (([IO.File]::ReadAllText($approval,[Text.Encoding]::ASCII).Trim()) -eq 'ALLOW_DAILY_CRM_UPDATE=YES;SOURCE=TEST_NEWBASE;MAX_PER_RUN=1;NO_DELETE=YES') 'APPROVAL_NOT_MATCHED'
   Need (Stable $OnecGuid $stamp) 'SOURCE_CHANGED_BEFORE_WRITE'
  $phase='CRM_APPLY'
   $null=Query ("BEGIN IMMEDIATE;UPDATE msp_daily_queue SET state='INTENT' WHERE onec_guid='"+$OnecGuid+"' AND state='PENDING' AND source_utc="+(Lit $stamp)+";CREATE TEMP TABLE _guard(n INTEGER NOT NULL CHECK(n=1));INSERT INTO _guard SELECT changes();COMMIT;")
   $intent=$true
  $null=Query "CREATE TABLE IF NOT EXISTS msp_auto_ops(onec_guid TEXT PRIMARY KEY,operation TEXT NOT NULL,crm_id INTEGER NOT NULL,entity_kind TEXT NOT NULL,created_utc TEXT NOT NULL);"
  $changed=($itemState -eq 'DIFF' -or -not $reqMatch)
  if($changed){
   SqlStatus $OnecGuid 'DAILY_UPDATE_SENT' ([string]$id) $category
   if($itemState -eq 'DIFF'){
    $field=if($kind -eq 4){'title'}else{'name'}
    $cmd='crm.item.update?entityTypeId='+$kind+'&id='+$id+'&fields['+$field+']='+(Url $wanted)
    $script:writes++
    try{$null=Batch @($cmd)}catch{}
   }
   if($kind -eq 4 -and -not $reqMatch){
    $cmd='crm.requisite.update?id='+$reqId+'&fields[NAME]='+(Url $name)+'&fields[RQ_COMPANY_NAME]='+(Url $name)+'&fields[RQ_COMPANY_FULL_NAME]='+(Url $full)+'&fields[RQ_INN]='+$inn
    $script:writes++
    try{$null=Batch @($cmd)}catch{}
   }
  }
  $phase='CRM_BACKREAD'
  Need ((ReadItem $kind $id $OnecGuid $wanted) -eq 'MATCH') 'ITEM_BACKREAD_MISMATCH'
  if($kind -eq 4){Need (ReadRequisite $reqId $id $name $full $inn) 'REQUISITE_BACKREAD_MISMATCH'}
  Need (Stable $OnecGuid $stamp) 'SOURCE_CHANGED_DURING_WRITE'
  $phase='LOCAL_EXACT_ACK'
  Done $OnecGuid $stamp $id $kind
   $intent=$false
  'CRM_WRITES='+$script:writes
  'BACKREAD=PASS'
  'SOURCE_EVENT_ACK=EXACT_VERSION'
  'ONEC_WRITES=0'
  'RESULT=PASS;STAGE=MSP_DAILY_CRM_APPLY_V1'
 }finally{
  if($locked){$mutex.ReleaseMutex()}
  if($null -ne $mutex){$mutex.Dispose()}
 }
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'CRM_WRITE_ATTEMPTS='+$script:writes
 'RESULT=FAIL;STAGE=MSP_DAILY_CRM_V1;GATE='+$gate+';PHASE='+$phase
 if($intent -and $guid -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'){
   try{$null=Query ("UPDATE msp_daily_queue SET state='UNCERTAIN' WHERE onec_guid='"+$guid+"' AND state='INTENT';")}catch{}
  }
  'NO_BLIND_RETRY=YES'
 exit 1
}finally{
 $script:base=$null
}

#requires -version 2
# Direct Bitrix24 batch delivery for new TEST NewBase companies/contacts (no 1C changes).
# Source refresh queues changed GUIDs; this stage transfers new buyers by batch.
param([string]$ExpectedComputerName='SRV',[int]$MaxRows=20)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root;$phase='PRECHECK'
$script:created=0;$script:linked=0;$script:held=0;$script:confirmed=0;$script:uncertain=0
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Hold([string]$Guid,[string]$Reason){
 $null=Query ("UPDATE msp_auto_outbox SET change_kind='HELD' WHERE onec_guid='"+$Guid+"';")
 $script:held++
}
function Entity([string]$Kind){if($Kind -eq 'LEGAL'){return 4};if($Kind -eq 'PERSON'){return 3};Fail 'TYPE_UNKNOWN'}
function Guard([string]$Value){if($Value.Length -gt 160 -or $Value.Length -eq 0){return $false};return $true}
function CmdResult([string]$Res,[int]$Idx,[string]$FieldPath){
 $k='k'+$Idx
 $path="'$.result.result."+$k+$FieldPath+"'"
 $expr="CASE WHEN json_type(doc,"+$path+") IN ('integer','text') THEN CAST(json_extract(doc,"+$path+") AS TEXT) ELSE 'INVALID' END"
 return BResult $Res $Idx $expr
}
function ListId([string]$Res,[int]$Idx,[bool]$Requisite){
 $k='k'+$Idx
 if($Requisite){
  $p="'$.result.result."+$k+"'"
  $x="CASE WHEN json_type(doc,"+$p+")<>'array' THEN 'INVALID' WHEN json_array_length(doc,"+$p+")=0 THEN 'NONE' WHEN json_array_length(doc,"+$p+")>1 THEN 'MULTIPLE' WHEN coalesce(json_type(doc,'$.result.result_next."+$k+"'),'null')<>'null' THEN 'PAGING' ELSE CAST(json_extract(doc,"+$p+"||'[0].ID') AS TEXT) END"
 }else{
  $p="'$.result.result."+$k+".items'"
  $x="CASE WHEN json_type(doc,"+$p+")<>'array' THEN 'INVALID' WHEN json_array_length(doc,"+$p+")=0 THEN 'NONE' WHEN json_array_length(doc,"+$p+")>1 THEN 'MULTIPLE' WHEN coalesce(json_type(doc,'$.result.result_next."+$k+"'),'null')<>'null' THEN 'PAGING' ELSE CAST(json_extract(doc,"+$p+"||'[0].id') AS TEXT) END"
 }
 return BResult $Res $Idx $x
}
$mt=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspNewbaseBitrixPumpV2');$locked=$false
try{
 if(-not $mt.WaitOne(0,$false)){Fail 'PUMP_ALREADY_RUNNING'}
 $locked=$true
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_ONLY'}
 if($MaxRows -lt 1 -or $MaxRows -gt 20){Fail 'MAX_ROWS_LIMIT'}
 $initial=Join-Path $root 'state\msp-newbase-auto-source-status.txt'
 if(-not [IO.File]::Exists($initial)){Fail 'SOURCE_REFRESH_REQUIRED'}
 if([IO.File]::ReadAllText($initial,[Text.Encoding]::ASCII) -notmatch 'STATUS=PASS;SOURCE=TEST_NEWBASE'){Fail 'SOURCE_NOT_ACCEPTED'}
 $schema="CREATE TABLE IF NOT EXISTS msp_auto_map(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,entity_kind INTEGER NOT NULL,mapped_utc TEXT NOT NULL);CREATE TABLE IF NOT EXISTS msp_auto_ops(onec_guid TEXT PRIMARY KEY,operation TEXT NOT NULL,crm_id INTEGER NOT NULL,entity_kind TEXT NOT NULL,created_utc TEXT NOT NULL);"
 $null=Query $schema
 $phase='SOURCE_PENDING_ROWS'
 $q="SELECT c.onec_guid||'|'||c.onec_type||'|'||hex(CAST(coalesce(nullif(trim(c.name_short),''),trim(c.name_full),'') AS BLOB))||'|'||hex(CAST(coalesce(trim(c.name_full),'') AS BLOB))||'|'||hex(CAST(coalesce(nullif(trim(c.person_name),''),nullif(trim(c.name_full),''),trim(c.name_short),'') AS BLOB))||'|'||hex(CAST(coalesce(trim(c.inn),'') AS BLOB)) FROM msp_auto_outbox o JOIN customers c ON c.onec_guid=o.onec_guid WHERE o.change_kind='UPSERT' AND c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND c.needs_review=0 AND c.onec_type IN ('LEGAL','PERSON') AND NOT EXISTS(SELECT 1 FROM msp_auto_ops p WHERE p.onec_guid=o.onec_guid) ORDER BY o.onec_guid LIMIT "+$MaxRows+";"
 $lines=Query $q
 if($lines.Length -eq 0){
  'PENDING_ELIGIBLE_ITEMS=0'
  'RESULT=PASS;STAGE=NEWBASE_CRM_BATCH_V2'
  exit 0
 }
 $rows=New-Object Collections.ArrayList
 foreach($line in ($lines -split '\r?\n')){
  $v=$line.Split('|')
  if($v.Length -ne 6){Fail 'SOURCE_ROW_SHAPE'}
  $g=$v[0]
  if($g -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'){Fail 'SOURCE_GUID_SHAPE'}
  $kind=$v[1];$entity=Entity $kind
  $name=Unhex $v[2];$full=Unhex $v[3];$person=Unhex $v[4];$inn=Unhex $v[5]
  if($kind -eq 'LEGAL' -and -not (Guard $name)){Hold $g 'NAME';continue}
  if($kind -eq 'PERSON' -and -not (Guard $person)){Hold $g 'PERSON';continue}
  if($inn.Length -gt 0 -and $inn -notmatch '^(?:[0-9]{10}|[0-9]{12})$' -and $kind -eq 'LEGAL'){Hold $g 'INN';continue}
  if($full.Length -eq 0){$full=$name}
  if($full.Length -gt 256){Hold $g 'FULL';continue}
  $row=New-Object PSObject -Property @{guid=$g;kind=$kind;entity=$entity;name=$name;full=$full;person=$person;inn=$inn;crmId=0;existing=$false}
  [void]$rows.Add($row)
 }
 if($rows.Count -eq 0){'HELD='+$script:held;'RESULT=PASS;STAGE=NEWBASE_CRM_BATCH_V2';exit 0}
 Secret
 $phase='BATCH_ORIGIN_SEARCH'
 $query=New-Object Collections.ArrayList
 foreach($item in $rows){
  $cmd='crm.item.list?entityTypeId='+$item.entity+'&filter[originatorId]=MSP_ONEC_NEWBASE&filter[originId]='+$item.guid+'&select[0]=id&start=0'
  [void]$query.Add($cmd)
 }
 $reply=Batch @($query.ToArray())
 $new=New-Object Collections.ArrayList
 for($i=0;$i -lt $rows.Count;$i++){
  $item=$rows[$i]
  $id=ListId $reply $i $false
  if($id -eq 'NONE'){[void]$new.Add($item)}
  elseif($id -match '^[1-9][0-9]{0,9}$'){$item.crmId=[int]$id;$item.existing=$true}
  else{Fail 'ORIGIN_BATCH_UNCERTAIN'}
 }
 $phase='BATCH_DUPLICATE_SCREEN'
 $safe=New-Object Collections.ArrayList
 if($new.Count -gt 0){
  $checks=New-Object Collections.ArrayList
  foreach($item in $new){
   # A repeated full name is NOT evidence of duplicate physical buyers.
   if($item.kind -eq 'PERSON'){continue}
   [void]$checks.Add(('crm.item.list?entityTypeId=4&filter[title]='+(Url $item.name)+'&select[0]=id&start=0'))
   if($item.inn.Length -gt 0){[void]$checks.Add(('crm.requisite.list?filter[RQ_INN]='+(Url $item.inn)+'&select[0]=ID&start=0'))}
  }
  if($checks.Count -gt 50){Fail 'SCREEN_BATCH_OVERFLOW'}
  $screen=$null
  if($checks.Count -gt 0){$screen=Batch @($checks.ToArray())}
  $checkIndex=0
  foreach($item in $new){
   if($item.kind -eq 'PERSON'){[void]$safe.Add($item);continue}
   $nameExisting=ListId $screen $checkIndex $false;$checkIndex++
   if(@('INVALID','MULTIPLE','PAGING','MISSING','ERROR') -contains $nameExisting){Fail 'NAME_SCREEN_UNCERTAIN'}
   $innExisting='NONE'
   if($item.inn.Length -gt 0){
    $innExisting=ListId $screen $checkIndex $true;$checkIndex++
    if(@('INVALID','MULTIPLE','PAGING','MISSING','ERROR') -contains $innExisting){Fail 'INN_SCREEN_UNCERTAIN'}
   }
   if($nameExisting -eq 'NONE' -and $innExisting -eq 'NONE'){[void]$safe.Add($item)}
   else{Hold $item.guid 'CRM_POSSIBLE_DUPLICATE'}
  }
 }
 $phase='BATCH_COMPANY_CONTACT_ADD'
 $cmds=New-Object Collections.ArrayList
 $creates=New-Object Collections.ArrayList
 foreach($item in $safe){
  if($cmds.Count -ge 39){break}
  $field='fields[title]';$value=$item.name
  if($item.kind -eq 'PERSON'){$field='fields[name]';$value=$item.person}
  $query='crm.item.add?entityTypeId='+$item.entity+'&'+$field+'='+(Url $value)+'&fields[originatorId]=MSP_ONEC_NEWBASE&fields[originId]='+$item.guid
  [void]$cmds.Add($query)
  $item | Add-Member -MemberType NoteProperty -Name cmdAdd -Value ($cmds.Count-1)
  [void]$creates.Add($item)
  if($item.kind -eq 'LEGAL' -and $item.inn.Length -gt 0){
   $link='$result[k'+$item.cmdAdd+'][item][id]'
   $rq='crm.requisite.add?fields[ENTITY_TYPE_ID]=4&fields[ENTITY_ID]='+$link+'&fields[PRESET_ID]=1&fields[NAME]='+(Url $item.name)+'&fields[RQ_COMPANY_NAME]='+(Url $item.name)+'&fields[RQ_COMPANY_FULL_NAME]='+(Url $item.full)+'&fields[RQ_INN]='+$item.inn
   [void]$cmds.Add($rq)
   $item | Add-Member -MemberType NoteProperty -Name cmdReq -Value ($cmds.Count-1)
  }else{$item | Add-Member -MemberType NoteProperty -Name cmdReq -Value -1}
 }
 if($cmds.Count -gt 0){
  $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  $sql=New-Object Text.StringBuilder
  [void]$sql.AppendLine('BEGIN IMMEDIATE;')
  foreach($item in $creates){
   [void]$sql.AppendLine("INSERT INTO msp_auto_ops(onec_guid,operation,crm_id,entity_kind,created_utc) VALUES ('"+$item.guid+"','CREATE_SENT',0,'"+$item.kind+"','"+$stamp+"');")
  }
  [void]$sql.AppendLine('COMMIT;')
  $null=Query $sql.ToString()
  $send=Batch @($cmds.ToArray())
  foreach($item in $creates){
   $id=CmdResult $send $item.cmdAdd '.item.id'
   if($id -match '^[1-9][0-9]{0,9}$'){
    $item.crmId=[int]$id
    SqlStatus $item.guid 'CREATED' $id $item.kind
   }else{$script:uncertain++}
  }
  $phase='BATCH_VERIFY_CREATED'
  $verify=New-Object Collections.ArrayList
  $toVerify=New-Object Collections.ArrayList
  foreach($item in $creates){
   if($item.crmId -le 0){continue}
   [void]$verify.Add('crm.item.get?entityTypeId='+$item.entity+'&id='+$item.crmId)
   [void]$toVerify.Add($item)
  }
  $verified=$null
  if($verify.Count -gt 0){$verified=Batch @($verify.ToArray())}
  for($i=0;$i -lt $toVerify.Count;$i++){
   $item=$toVerify[$i]
   $idBack=CmdResult $verified $i '.item.id'
   $guidBack=CmdResult $verified $i '.item.originId'
   $originBack=CmdResult $verified $i '.item.originatorId'
   if($idBack -ne [string]$item.crmId -or $guidBack -ne $item.guid -or $originBack -ne 'MSP_ONEC_NEWBASE'){Fail 'CREATED_BACKREAD_MISMATCH'}
   if($item.cmdReq -ge 0){
    $rid=CmdResult $send $item.cmdReq ''
    if($rid -notmatch '^[1-9][0-9]{0,9}$'){Fail 'CREATED_REQUISITE_UNCONFIRMED'}
   }
   MarkDone $item.guid $item.crmId $item.entity
   $script:created++;$script:confirmed++
  }
 }
 $phase='EXISTING_ORIGIN_MAPPING'
 foreach($item in $rows){
  if(-not $item.existing){continue}
  MarkDone $item.guid $item.crmId $item.entity
  $script:linked++;$script:confirmed++
 }
 'NEWBASE_BATCH_SOURCE='+$rows.Count
 'CREATED_AND_VERIFIED='+$script:created
 'EXISTING_BY_ORIGIN='+$script:linked
 'HELD_POSSIBLE_DUPLICATES='+$script:held
 'UNRESOLVED_WRITES='+$script:uncertain
 'OUTBOX_PROGRESS_PERSISTED=YES'
 'SOURCE_1C_WRITES=NO'
 'SOURCE_SQLITE_RECORDS_NOT_MODIFIED=YES'
 if($script:uncertain -gt 0){'RESULT=PARTIAL;STAGE=NEWBASE_CRM_BATCH_V2'}else{'RESULT=PASS;STAGE=NEWBASE_CRM_BATCH_V2'}
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=NEWBASE_CRM_BATCH_V2;GATE='+$gate+';PHASE='+$phase
 'NO_BLIND_RETRY=YES'
 exit 1
}finally{
 if($locked){$mt.ReleaseMutex()};if($null -ne $mt){$mt.Dispose()}
 $script:base=$null
}

#requires -version 2
# One-time import of every active TEST NewBase buyer (including PERSON and REVIEW).
# LocalService only. Source is SRV SQLite. No 1C requests/writes.
# CRM writes only as explicit job invocation. Never scheduled by this file.
param([string]$ExpectedComputerName='SRV',[int]$MaxBatches=800,[int]$BatchSize=10)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$script:root=$root
$phase='PRECHECK';$locked=$false;$mutex=$null
$script:created=0;$script:reused=0;$script:processed=0
$state=Join-Path $root 'state\bitrix-initial-all-buyers-v3.status'
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'msp-newbase-bitrix-core-v2.ps1')
function Require([bool]$Condition,[string]$Code){if(-not $Condition){Fail $Code}}
function Number([string]$Text){
 if($Text -notmatch '^[0-9]{1,10}$'){Fail 'COUNT_INVALID'}
 return [int]$Text
}
function SaveStatus([string]$Value){
 [IO.File]::WriteAllText($state,('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';'+$Value),[Text.Encoding]::ASCII)
}
function SqlRead([string]$Sql){
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$exe
 $psi.Arguments='-readonly -batch -bail "'+$db+'"'
 $psi.UseShellExecute=$false
 $psi.RedirectStandardInput=$true
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 $psi.CreateNoWindow=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$psi
 try{
  if(-not $p.Start()){Fail 'SQLITE_PROCESS_START_FAILED'}
  $p.StandardInput.WriteLine($Sql);$p.StandardInput.Close()
  $result=$p.StandardOutput.ReadToEnd()
  $errorText=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'SQLITE_QUERY_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $errorText.Trim().Length -gt 0){Fail 'SQLITE_QUERY_FAILED'}
  if($result.Length -gt 524288){Fail 'SQLITE_RESULT_TOO_LARGE'}
  return $result.Trim()
 }finally{$p.Close()}
}
function DecodeHex([string]$H){
 if(($H.Length % 2) -ne 0 -or $H.Length -gt 16384 -or $H -notmatch '^[A-Fa-f0-9]*$'){Fail 'SOURCE_HEX_INVALID'}
 $b=New-Object byte[] ($H.Length/2)
 for($i=0;$i -lt $b.Length;$i++){$b[$i]=[Convert]::ToByte($H.Substring($i*2,2),16)}
 return [Text.Encoding]::UTF8.GetString($b)
}
function Rows([string]$Data){
 $list=New-Object Collections.ArrayList
 if($Data.Length -eq 0){return ,$list}
 foreach($line in ($Data -split '\r?\n')){
  $v=$line.Split('|')
  if($v.Count -ne 6){Fail 'ROW_SHAPE_INVALID'}
  $guid=$v[0]
  if($guid -notmatch '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$'){Fail 'GUID_INVALID'}
  $category=$v[1]
  if(@('LEGAL','PERSON','REVIEW') -notcontains $category){Fail 'CATEGORY_INVALID'}
  $short=DecodeHex $v[2];$full=DecodeHex $v[3];$person=DecodeHex $v[4];$inn=DecodeHex $v[5]
  $kind=if($category -eq 'PERSON'){3}else{4}
  $title=if($kind -eq 3){$person}else{$short}
  if($title.Trim().Length -eq 0){$title=if($full.Trim().Length -gt 0){$full}else{'[1C UNNAMED] '+$guid}}
  if($category -eq 'REVIEW'){$title='[1C TYPE REVIEW] '+$title}
  if($title.Length -gt 240){$title=$title.Substring(0,240)}
  $item=New-Object PSObject -Property @{guid=$guid;category=$category;kind=$kind;title=$title;full=$full;inn=$inn}
  [void]$list.Add($item)
 }
 return ,$list
}
function Details($Item){
 # Visible information from existing TEST source, never invented data.
 $text='Source=1C NewBase; Type='+$Item.category
 if($Item.kind -eq 4){
  if($Item.full.Trim().Length -gt 0){$text+='; FullName='+$Item.full}
  if($Item.inn.Trim().Length -gt 0){$text+='; INN='+$Item.inn}
 }else{
  $text+='; Name='+$Item.title
 }
 if($text.Length -gt 1600){Fail 'DETAILS_TOO_LARGE'}
 return $text
}
function Extract([string]$Reply,[int]$I,[string]$Path){
 $key='k'+$I
 $p="'$.result.result."+$key+$Path+"'"
 $expr="CASE WHEN json_type(doc,"+$p+") IN ('integer','text') THEN CAST(json_extract(doc,"+$p+") AS TEXT) ELSE 'INVALID' END"
 return BResult $Reply $I $expr
}
function Found([string]$Reply,[int]$I){
 $key='k'+$I
 $p="'$.result.result."+$key+".items'"
 $expr="CASE WHEN json_type(doc,"+$p+")<>'array' THEN 'INVALID' WHEN json_array_length(doc,"+$p+")>1 THEN 'MULTIPLE' WHEN coalesce(json_type(doc,'$.result.result_next."+$key+"'),'null')<>'null' THEN 'PAGING' WHEN json_array_length(doc,"+$p+")=0 THEN 'NONE' ELSE CAST(json_extract(doc,"+$p+"||'[0].id') AS TEXT) END"
 return BResult $Reply $I $expr
}
function Search($Items){
 $commands=New-Object Collections.ArrayList
 foreach($x in $Items){
  [void]$commands.Add('crm.item.list?entityTypeId='+$x.kind+'&filter[originatorId]=MSP_ONEC_NEWBASE&filter[originId]='+$x.guid+'&select[0]=id&start=0')
 }
 $answer=Batch @($commands.ToArray())
 $out=New-Object Collections.ArrayList
 for($i=0;$i -lt $Items.Count;$i++){
  $found=Found $answer $i
  [void]$out.Add($found)
 }
 return ,$out
}
function Verify($Items,$Ids){
 $q=New-Object Collections.ArrayList
 for($i=0;$i -lt $Items.Count;$i++){
  [void]$q.Add('crm.item.get?entityTypeId='+$Items[$i].kind+'&id='+$Ids[$i])
 }
 $answer=Batch @($q.ToArray())
 $review=New-Object Collections.ArrayList
 for($i=0;$i -lt $Items.Count;$i++){
  $rId=Extract $answer $i '.item.id'
  $rOrigin=Extract $answer $i '.item.originId'
  $rOwner=Extract $answer $i '.item.originatorId'
  if($rId -ne [string]$Ids[$i] -or $rOrigin -ne $Items[$i].guid -or $rOwner -ne 'MSP_ONEC_NEWBASE'){Fail 'CRM_BACKREAD_ORIGIN_MISMATCH'}
  $key='k'+$i
  $field=if($Items[$i].kind -eq 3){'name'}else{'title'}
  $path="'$.result.result."+$key+".item."+$field+"'"
  $want=HexUtf8 ([string]$Items[$i].title)
  $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN hex(CAST(coalesce(json_extract(doc,"+$path+"),'') AS BLOB))='"+$want+"' THEN 'MATCH' ELSE 'DIFF' END FROM j;"
  if((SqlJson $answer $sql) -ne 'MATCH'){Fail 'CRM_VISIBLE_NAME_MISMATCH'}
  $path="'$.result.result."+$key+".item.comments'"
  $want=HexUtf8 (Details $Items[$i])
  $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN hex(CAST(coalesce(json_extract(doc,"+$path+"),'') AS BLOB))='"+$want+"' THEN 'MATCH' ELSE 'DIFF' END FROM j;"
  $details=SqlJson $answer $sql
  if($details -notin @('MATCH','DIFF')){Fail 'CRM_COMMENTS_READ_INVALID'}
  [void]$review.Add($details)
 }
 return ,$review
}
function CommitMap($Items,$Ids,$Review){
 Require ($Items.Count -eq $Ids.Count -and $Ids.Count -eq $Review.Count) 'MAP_REVIEW_COUNT_MISMATCH'
 $sql=New-Object Text.StringBuilder
 [void]$sql.Append('BEGIN IMMEDIATE;')
 for($i=0;$i -lt $Items.Count;$i++){
  $g=$Items[$i].guid;$id=[int]$Ids[$i];$kind=[int]$Items[$i].kind
  Require ($id -gt 0) 'CRM_ID_INVALID'
  [void]$sql.Append("INSERT INTO msp_initial_map(onec_guid,crm_id,entity_kind,mapped_utc) VALUES ('"+$g+"',"+$id+","+$kind+",datetime('now')) ON CONFLICT(onec_guid) DO UPDATE SET crm_id=excluded.crm_id,entity_kind=excluded.entity_kind,mapped_utc=excluded.mapped_utc;")
  if($Review[$i] -eq 'DIFF'){
   [void]$sql.Append("INSERT INTO msp_initial_details_review(onec_guid,crm_id,detail_state,created_utc) VALUES ('"+$g+"',"+$id+",'COMMENTS_MISMATCH',datetime('now')) ON CONFLICT(onec_guid) DO UPDATE SET crm_id=excluded.crm_id,detail_state=excluded.detail_state,created_utc=excluded.created_utc;")
  }elseif($Review[$i] -ne 'MATCH'){Fail 'UNEXPECTED_REVIEW_STATE'}
  [void]$sql.Append("DELETE FROM msp_initial_inflight WHERE onec_guid='"+$g+"';")
 }
 [void]$sql.Append('COMMIT;')
 $null=Query $sql.ToString()
}
try{
 Require ($ExpectedComputerName -eq 'SRV' -and $env:COMPUTERNAME -eq 'SRV') 'HOST_REQUIRED'
 Require ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Require ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_REQUIRED'
 Require ($BatchSize -ge 1 -and $BatchSize -le 20 -and $MaxBatches -ge 1 -and $MaxBatches -le 800) 'BOUNDS_INVALID'
 foreach($rel in @('data\customers.db','bin\sqlite3.exe','bin\curl.exe','config\curl-ca-bundle.crt','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi','state\customer-initial-load-accepted.txt')){
  $f=Join-Path $root $rel
  Require ([IO.File]::Exists($f)) 'MACHINE_COMPONENT_MISSING'
  Require (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_COMPONENT_DENIED'
 }
 $mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspOneTimeAllBuyersImportV3')
 Require ($mutex.WaitOne(0,$false)) 'IMPORT_ALREADY_RUNNING'
 $locked=$true
 $phase='SQLITE_SOURCE_ACCEPTANCE'
 Require ((SqlRead 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_INTEGRITY_FAILED'
 $counts=SqlRead "SELECT count(*)||':'||sum(onec_type='LEGAL')||':'||sum(onec_type='PERSON')||':'||sum(onec_type='REVIEW') FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;"
 Require ($counts -eq '6433:1941:4486:6') 'SOURCE_POPULATION_CHANGED'
 $schema="CREATE TABLE IF NOT EXISTS msp_initial_map(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,entity_kind INTEGER NOT NULL,mapped_utc TEXT NOT NULL);CREATE TABLE IF NOT EXISTS msp_initial_inflight(onec_guid TEXT PRIMARY KEY,crm_type INTEGER NOT NULL,attempt_utc TEXT NOT NULL);CREATE TABLE IF NOT EXISTS msp_initial_details_review(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,detail_state TEXT NOT NULL,created_utc TEXT NOT NULL);"
 $null=Query $schema
 $phase='BITRIX_CREDENTIAL'
 Secret
 for($loop=0;$loop -lt $MaxBatches;$loop++){
  $phase='READ_SOURCE_SQL'
  $query="SELECT c.onec_guid||'|'||c.onec_type||'|'||hex(CAST(coalesce(c.name_short,'') AS BLOB))||'|'||hex(CAST(coalesce(c.name_full,'') AS BLOB))||'|'||hex(CAST(coalesce(c.person_name,'') AS BLOB))||'|'||hex(CAST(coalesce(c.inn,'') AS BLOB)) FROM customers c WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND NOT EXISTS(SELECT 1 FROM msp_initial_map m WHERE m.onec_guid=c.onec_guid) ORDER BY c.onec_guid LIMIT "+$BatchSize+";"
  $pending=SqlRead $query
  $phase='READ_SOURCE_PARSE'
  if($pending -eq ''){break}
  $items=Rows $pending
  Require ($items.Count -ge 1 -and $items.Count -le $BatchSize) 'SOURCE_BATCH_INVALID'
  $phase='CRM_ORIGIN_SEARCH'
  $existing=Search $items
  $already=New-Object Collections.ArrayList
  $alreadyIds=New-Object Collections.ArrayList
  $new=New-Object Collections.ArrayList
  for($i=0;$i -lt $items.Count;$i++){
   $id=[string]$existing[$i]
   if($id -eq 'NONE'){
    $inflight=SqlRead ("SELECT count(*) FROM msp_initial_inflight WHERE onec_guid='"+$items[$i].guid+"';")
    if($inflight -ne '0'){Fail 'PRIOR_CREATE_UNCERTAIN_MANUAL_RECONCILE'}
    [void]$new.Add($items[$i])
   }elseif($id -match '^[1-9][0-9]{0,9}$'){
    [void]$already.Add($items[$i]);[void]$alreadyIds.Add([int]$id)
   }else{Fail 'ORIGIN_SEARCH_AMBIGUOUS'}
  }
  if($already.Count -gt 0){
   $phase='VERIFY_EXISTING'
   $existingReview=Verify $already $alreadyIds
   CommitMap $already $alreadyIds $existingReview
   $script:reused+=$already.Count;$script:processed+=$already.Count
  }
  if($new.Count -gt 0){
   $phase='PERSIST_BEFORE_CREATE'
   $sql=New-Object Text.StringBuilder
   [void]$sql.Append('BEGIN IMMEDIATE;')
   foreach($item in $new){
    [void]$sql.Append("INSERT INTO msp_initial_inflight(onec_guid,crm_type,attempt_utc) VALUES ('"+$item.guid+"',"+$item.kind+",datetime('now')) ON CONFLICT(onec_guid) DO NOTHING;")
   }
   [void]$sql.Append('COMMIT;')
   $null=Query $sql.ToString()
   $phase='CRM_CREATE_BATCH'
   $commands=New-Object Collections.ArrayList
   foreach($item in $new){
    $field=if($item.kind -eq 3){'name'}else{'title'}
    $cmd='crm.item.add?entityTypeId='+$item.kind+'&fields['+$field+']='+(Url $item.title)+'&fields[originatorId]=MSP_ONEC_NEWBASE&fields[originId]='+$item.guid
    $cmd+='&fields[comments]='+(Url (Details $item))
    [void]$commands.Add($cmd)
   }
   $reply=Batch @($commands.ToArray())
   $ids=New-Object Collections.ArrayList
   for($i=0;$i -lt $new.Count;$i++){
    $id=Extract $reply $i '.item.id'
    if($id -notmatch '^[1-9][0-9]{0,9}$'){Fail 'CREATE_RESULT_AMBIGUOUS_NO_RETRY'}
    [void]$ids.Add([int]$id)
   }
   $phase='CRM_CREATE_BACKREAD'
   $newReview=Verify $new $ids
   CommitMap $new $ids $newReview
   $script:created+=$new.Count;$script:processed+=$new.Count
  }
  $total=SqlRead 'SELECT count(*) FROM msp_initial_map;'
  $reviews=SqlRead 'SELECT count(*) FROM msp_initial_details_review;'
  SaveStatus ('STATUS=RUNNING;MAPPED='+$total+';TARGET=6433;COMMENTS_REVIEW='+$reviews+';CREATED_THIS_RUN='+$script:created+';FOUND_THIS_RUN='+$script:reused+';SOURCE=TEST_NEWBASE')
  Start-Sleep -Milliseconds 800
 }
 $phase='FINAL_RECONCILIATION'
 $done=SqlRead 'SELECT count(*) FROM msp_initial_map;'
 $inflight=SqlRead 'SELECT count(*) FROM msp_initial_inflight;'
 $gaps=SqlRead 'SELECT count(*) FROM customers c WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND NOT EXISTS(SELECT 1 FROM msp_initial_map m WHERE m.onec_guid=c.onec_guid);'
 $reviews=SqlRead 'SELECT count(*) FROM msp_initial_details_review;'
 if($done -eq '6433' -and $inflight -eq '0' -and $gaps -eq '0'){
  $status=if($reviews -eq '0'){'PASS'}else{'PASS_WITH_DETAILS_REVIEW'}
  SaveStatus ('STATUS='+$status+';MAPPED=6433;TARGET=6433;COMMENTS_REVIEW='+$reviews+';SOURCE=TEST_NEWBASE;AUTO_UPDATE=OFF;ONEC_WRITES=0')
  'TOTAL_IN_CRM_IDENTITY_AND_NAME_VERIFIED=6433'
  'CRM_COMMENTS_REQUIRE_REVIEW='+$reviews
  'RESULT=PASS;STAGE=NEWBASE_ALL_BUYERS_INITIAL_CRM_IMPORT_V3'
 }else{
  SaveStatus ('STATUS=PARTIAL;MAPPED='+$done+';TARGET=6433;INFLIGHT='+$inflight+';GAPS='+$gaps+';COMMENTS_REVIEW='+$reviews+';SOURCE=TEST_NEWBASE')
  'CRM_VERIFIED_TOTAL='+$done
  'CRM_COMMENTS_REQUIRE_REVIEW='+$reviews
  'CRM_UNRESOLVED_INFLIGHT='+$inflight
  'CRM_NOT_YET_MAPPED='+$gaps
  'RESULT=PARTIAL;STAGE=NEWBASE_ALL_BUYERS_INITIAL_CRM_IMPORT_V2'
 }
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 $type=$_.Exception.GetType().Name.ToUpperInvariant()
 $errorId=([string]$_.FullyQualifiedErrorId).ToUpperInvariant()
 if($type -notmatch '^[A-Z0-9_]{1,70}$'){$type='OTHER'}
 if($errorId -notmatch '^[A-Z0-9_.]{1,100}$'){$errorId='OTHER'}
 $line=[int]$_.InvocationInfo.ScriptLineNumber
 try{$total=SqlRead 'SELECT count(*) FROM msp_initial_map;';SaveStatus ('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase+';EXCEPTION_TYPE='+$type+';ERROR_ID='+$errorId+';ERROR_LINE='+$line+';MAPPED='+$total+';TARGET=6433')}catch{}
 'IMPORT_FAILURE_GATE='+$gate
 'IMPORT_FAILURE_PHASE='+$phase
 'NO_BLIND_RETRY=YES'
 'RESULT=FAIL;STAGE=NEWBASE_ALL_BUYERS_INITIAL_CRM_IMPORT_V2'
 exit 1
}finally{
 if($locked){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Dispose()}
 $script:base=$null
}

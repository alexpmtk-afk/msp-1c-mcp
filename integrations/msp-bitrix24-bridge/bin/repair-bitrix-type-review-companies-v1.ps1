#requires -version 2
# TEST NewBase: one-shot six existing Bitrix24 company title repairs, never change CRM entity type.
# Run as LOCAL SERVICE on physical SRV. No source 1C calls, no CRM creates/deletes, no repeat of uncertain POST.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$script:root='C:\ProgramData\MspCustomerStore'
$root=$script:root
$status=Join-Path $root 'state\msp-bitrix-type-review-company-fix-v1.status'
$journal=Join-Path $root 'state\msp-bitrix-type-review-company-fix-v1.journal'
$backup=Join-Path $root 'data\customers.before-type-review-company-fix-v1.sqlite.bak'
$proof=Join-Path $root 'state\msp-bitrix-unnamed-name-drain-v1.status'
$phase='PRECHECK';$posted=0;$verified=0;$locked=$false;$mutex=$null
$items=$null;$before=$null;$after=$null;$reply=$null
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Condition,[string]$Gate){if(-not $Condition){Fail $Gate}}
function CheckFile([string]$Path){
 Need ([IO.File]::Exists($Path)) 'COMPONENT_MISSING'
 Need (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
}
function ReadDb([string]$Sql){
 $pinfo=New-Object Diagnostics.ProcessStartInfo
 $pinfo.FileName=Join-Path $root 'bin\sqlite3.exe'
 $pinfo.Arguments='-readonly -batch -bail "'+(Join-Path $root 'data\customers.db')+'"'
 $pinfo.UseShellExecute=$false;$pinfo.CreateNoWindow=$true
 $pinfo.RedirectStandardInput=$true;$pinfo.RedirectStandardOutput=$true;$pinfo.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$pinfo
 try{
  Need ($p.Start()) 'SQLITE_START'
  $p.StandardInput.WriteLine($Sql);$p.StandardInput.Close()
  $output=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  Need ($p.ExitCode -eq 0 -and $err.Trim().Length -eq 0 -and $output.Length -le 22000) 'SQLITE_READ_FAILED'
  return $output
 }finally{$p.Close()}
}
function Counts(){
 return (ReadDb "SELECT count(*)||':'||coalesce(sum(state='DONE'),0)||':'||coalesce(sum(state='PENDING'),0)||':'||coalesce(sum(state='INTENT'),0)||':'||coalesce(sum(state='UNCERTAIN'),0) FROM msp_bitrix_type_review_fix;")
}
function Save([string]$Line){
 [IO.File]::WriteAllText($status,('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';'+$Line),[Text.Encoding]::ASCII)
}
function Cards([object[]]$List){
 $commands=New-Object Collections.ArrayList
 foreach($it in $List){[void]$commands.Add('crm.item.get?entityTypeId=4&id='+$it.id)}
 for($attempt=1;$attempt -le 3;$attempt++){
  try{return (Batch @($commands.ToArray()))}
  catch{
   if(@('NEWBASE_CURL_FAILED','NEWBASE_HTTP_429','NEWBASE_HTTP_503') -notcontains $_.Exception.Message -or $attempt -eq 3){throw}
   Start-Sleep -Seconds (2*$attempt)
  }
 }
 Fail 'GET_RETRIES_EXHAUSTED'
}
function CheckCard([string]$Reply,[int]$Index,[object]$Item,[bool]$After){
 $p='$.result.result.k'+$Index+'.item';$j="'"+$p+"'"
 $e="'$.result.result_error.k"+$Index+"'"
 $expect=if($After){$Item.newHex}else{$Item.oldHex}
 $q="SELECT CASE WHEN json_valid(doc)<>1 THEN 'BAD_JSON' WHEN json_type(doc,"+$e+") IS NOT NULL THEN 'REST_ERROR' WHEN coalesce(json_type(doc,"+$j+"),'missing')<>'object' THEN 'CARD_MISSING' WHEN coalesce(CAST(json_extract(doc,'"+$p+".id') AS TEXT),'')<>'"+$Item.id+"' THEN 'ID_CHANGED' WHEN coalesce(json_extract(doc,'"+$p+".originId'),'')<>'"+$Item.guid+"' OR coalesce(json_extract(doc,'"+$p+".originatorId'),'')<>'MSP_ONEC_NEWBASE' THEN 'ORIGIN_CHANGED' WHEN coalesce(json_type(doc,'"+$p+".fm'),'missing')<>'array' THEN 'FM_MISSING' WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".title'),'') AS BLOB))<>'"+$expect+"' THEN 'TITLE_MISMATCH'"
 if($After){
  $q+=" WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".fm'),'') AS BLOB))<>'"+$Item.fm+"' THEN 'FM_CHANGED'"
  $q+=" WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".comments'),'') AS BLOB))<>'"+$Item.comments+"' THEN 'COMMENTS_CHANGED'"
  $q+=" WHEN coalesce(CAST(json_extract(doc,'"+$p+".assignedById') AS TEXT),'')<>'"+$Item.assigned+"' THEN 'ASSIGNED_CHANGED'"
 }
 $q+=" ELSE 'PASS' END FROM j;"
 return (SqlJson $Reply $q)
}
function Grab([string]$Reply,[int]$Index,[string]$Field){
 $p="'$.result.result.k"+$Index+".item."+$Field+"'"
 return (SqlJson $Reply ("SELECT hex(CAST(coalesce(json_extract(doc,"+$p+"),'') AS BLOB)) FROM j;"))
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 Need (-not [IO.File]::Exists($status) -and -not [IO.File]::Exists($journal) -and -not [IO.File]::Exists($backup)) 'ALREADY_ATTEMPTED'
 foreach($file in @($proof,(Join-Path $root 'data\customers.db'),(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'bin\curl.exe'),(Join-Path $root 'config\curl-ca-bundle.crt'),(Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1'),(Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'))){CheckFile $file}
 $receipt=[IO.File]::ReadAllText($proof,[Text.Encoding]::ASCII).Trim()
 Need ($receipt -match 'STATUS=PASS;MODE=ONESHOT;SOURCE=TEST_NEWBASE;BATCHES=27;VERIFIED=525;CRM_WRITES=525;DONE=546;PENDING=0;INTENT=0;UNCERTAIN=0;BACKREAD=PASS;PHONE_EMAIL_PRESERVED=PASS;SQLITE_QUICK_CHECK=OK;ELAPSED_SECONDS=[0-9]+;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0') 'PREVIOUS_NAME_DRAIN_NOT_ACCEPTED'
 $mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspBitrixTypeReviewRepairV1')
 Need ($mutex.WaitOne(0,$false)) 'CONCURRENT_COMPANY_REPAIR';$locked=$true
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_INTEGRITY'
 $criteria="c.onec_type='REVIEW' AND c.buyer=1 AND c.invalid=0 AND c.deletion_mark=0 AND m.entity_kind=4 AND length(trim(coalesce(c.person_name,'')))=0 AND length(trim(coalesce(c.name_full,'')))>0 AND length(trim(coalesce(c.name_short,'')))>0"
 $source=ReadDb ("SELECT c.onec_guid||'|'||m.crm_id||'|'||hex(CAST(c.name_short AS BLOB)) FROM customers c JOIN msp_initial_map m ON m.onec_guid=c.onec_guid WHERE "+$criteria+" ORDER BY c.onec_guid;")
 $rows=@($source -split '\r?\n')
 Need ($rows.Count -eq 6) 'SIX_SOURCE_ROWS_REQUIRED'
 $counts=ReadDb ("SELECT count(*)||':'||count(DISTINCT c.onec_guid)||':'||count(DISTINCT m.crm_id)||':'||coalesce(sum(CASE WHEN length(trim(coalesce(c.inn,'')))>0 THEN 1 ELSE 0 END),0) FROM customers c JOIN msp_initial_map m ON m.onec_guid=c.onec_guid WHERE "+$criteria+";")
 Need ($counts -eq '6:6:6:1') 'SOURCE_CARDINALITY_CHANGED'
 $items=New-Object Collections.ArrayList
 foreach($line in $rows){
  $v=$line.Split('|')
  Need ($v.Count -eq 3 -and $v[0] -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$' -and $v[1] -match '^[1-9][0-9]{0,9}$') 'SOURCE_ID_INVALID'
  Need ($v[2] -match '^(?:[0-9A-F]{2}){1,480}$') 'SOURCE_NAME_HEX_INVALID'
  $name=Unhex $v[2]
  Need ($name.Trim().Length -gt 0 -and $name.Length -le 240 -and -not $name.StartsWith('[1C TYPE REVIEW]')) 'SOURCE_NAME_INVALID'
  $old='[1C TYPE REVIEW] '+$name
  if($old.Length -gt 240){$old=$old.Substring(0,240)}
  [void]$items.Add((New-Object PSObject -Property @{guid=$v[0];id=$v[1];new=$name;newHex=(HexUtf8 $name);oldHex=(HexUtf8 $old);fm='';comments='';assigned=''}))
 }
 $phase='CRM_PREFLIGHT'
 Secret
 $before=Cards @($items.ToArray())
 $cmds=New-Object Collections.ArrayList
 for($i=0;$i -lt $items.Count;$i++){
  $it=$items[$i]
  Need ((CheckCard $before $i $it $false) -eq 'PASS') 'CRM_PREIMAGE_CHANGED'
  $it.fm=Grab $before $i 'fm';$it.comments=Grab $before $i 'comments'
  $p="'$.result.result.k"+$i+".item.assignedById'"
  $it.assigned=SqlJson $before ("SELECT coalesce(CAST(json_extract(doc,"+$p+") AS TEXT),'') FROM j;")
  Need ($it.fm.Length -gt 0 -and $it.fm.Length -lt 8192 -and $it.comments.Length -lt 16384 -and $it.assigned -match '^[0-9]{0,10}$') 'CARD_PREIMAGE_BOUNDS'
  [void]$cmds.Add('crm.item.list?entityTypeId=4&filter[originatorId]=MSP_ONEC_NEWBASE&filter[originId]='+$it.guid+'&select[0]=id&start=0')
 }
 $list=Batch @($cmds.ToArray())
 for($i=0;$i -lt $items.Count;$i++){Need ((VerifyBatchList $list $i '.items') -eq $items[$i].id) 'ORIGIN_LOOKUP_CHANGED'}
 $phase='BACKUP'
 $null=Query (".backup '"+($backup.Replace('\','/'))+"'")
 CheckFile $backup
 Need ((ReadDb "ATTACH DATABASE 'file:C:/ProgramData/MspCustomerStore/data/customers.before-type-review-company-fix-v1.sqlite.bak?mode=ro' AS snap;PRAGMA snap.quick_check;") -eq 'ok') 'BACKUP_FAILED'
 $phase='INIT_QUEUE'
 $sql="BEGIN IMMEDIATE;CREATE TABLE msp_bitrix_type_review_fix(onec_guid TEXT PRIMARY KEY,crm_id INTEGER UNIQUE NOT NULL,state TEXT NOT NULL CHECK(state IN ('PENDING','INTENT','DONE','UNCERTAIN')),updated_utc TEXT,verified_utc TEXT);"
 foreach($it in $items){$sql+="INSERT INTO msp_bitrix_type_review_fix(onec_guid,crm_id,state,updated_utc) VALUES ('"+$it.guid+"',"+$it.id+",'PENDING',datetime('now'));";}
 $sql+="COMMIT;";$null=Query $sql
 Need ((Counts) -eq '6:0:6:0:0') 'QUEUE_INIT_FAILED'
 Save 'STATUS=RUNNING;MODE=ONESHOT;SOURCE=TEST_NEWBASE;VERIFIED=0;PENDING=6;INTENT=0;UNCERTAIN=0;CRM_WRITES=0;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 [IO.File]::WriteAllText($journal,'SOURCE=TEST_NEWBASE;TARGET=6;NO_PII=YES'+[Environment]::NewLine,[Text.Encoding]::ASCII)
 $phase='PERSIST_INTENT'
 $sql='BEGIN IMMEDIATE;'
 foreach($it in $items){$sql+="UPDATE msp_bitrix_type_review_fix SET state='INTENT',updated_utc=datetime('now') WHERE onec_guid='"+$it.guid+"' AND crm_id="+$it.id+" AND state='PENDING';CREATE TEMP TABLE IF NOT EXISTS _one(n INTEGER CHECK(n=1));INSERT INTO _one SELECT changes();DELETE FROM _one;";}
 $sql+='COMMIT;';$null=Query $sql
 Need ((Counts) -eq '6:0:0:6:0') 'INTENT_NOT_DURABLE'
 $phase='CRM_WRITE_ONCE'
 $cmds=New-Object Collections.ArrayList
 foreach($it in $items){[void]$cmds.Add('crm.item.update?entityTypeId=4&id='+$it.id+'&fields[title]='+(Url $it.new))}
 $posted=1
 $reply=Batch @($cmds.ToArray())  # Never repeat this POST after any error or ambiguous reply.
 $phase='CRM_INDEPENDENT_BACKREAD'
 $after=Cards @($items.ToArray())
 for($i=0;$i -lt $items.Count;$i++){
  $it=$items[$i]
  Need ((CheckCard $after $i $it $true) -eq 'PASS') 'BACKREAD_MISMATCH'
  $sql="BEGIN IMMEDIATE;UPDATE msp_bitrix_type_review_fix SET state='DONE',updated_utc=datetime('now'),verified_utc=datetime('now') WHERE onec_guid='"+$it.guid+"' AND crm_id="+$it.id+" AND state='INTENT';CREATE TEMP TABLE _one(n INTEGER CHECK(n=1));INSERT INTO _one SELECT changes();COMMIT;"
  $null=Query $sql;$verified++
 }
 Need ((Counts) -eq '6:6:0:0:0') 'QUEUE_FINAL_MISMATCH'
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'FINAL_SQLITE_INTEGRITY'
 $phase='FINAL'
 $msg='STATUS=PASS;MODE=ONESHOT;SOURCE=TEST_NEWBASE;TARGET=6;VERIFIED=6;CRM_WRITES=6;DONE=6;PENDING=0;INTENT=0;UNCERTAIN=0;BACKREAD=PASS;FM_COMMENTS_ASSIGNED_PRESERVED=PASS;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 Save $msg
 [IO.File]::AppendAllText($journal,('FINAL='+$msg+[Environment]::NewLine),[Text.Encoding]::ASCII)
 Get-Content $status
 'RESULT=PASS;STAGE=MSP_BITRIX_TYPE_REVIEW_COMPANY_FIX_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($phase -ne 'PRECHECK' -and $phase -ne 'CRM_PREFLIGHT' -and $phase -ne 'BACKUP'){
  try{$null=Query "UPDATE msp_bitrix_type_review_fix SET state='UNCERTAIN',updated_utc=datetime('now') WHERE state='INTENT';"}catch{}
 }
 $count='UNKNOWN';try{$count=Counts}catch{}
 try{Save ('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';VERIFIED='+$verified+';POST_ATTEMPTED='+$posted+';QUEUE='+$count+';ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0')}catch{}
 'RESULT=FAIL;STAGE=MSP_BITRIX_TYPE_REVIEW_COMPANY_FIX_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}finally{
 if($locked){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Close()}
 $script:base=$null;$items=$null;$before=$null;$after=$null;$reply=$null
}
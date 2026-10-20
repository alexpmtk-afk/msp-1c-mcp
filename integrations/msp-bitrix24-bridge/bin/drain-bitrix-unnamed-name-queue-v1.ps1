#requires -version 2
# ONE-SHOT drain of the 525 remaining historical unnamed contacts, TEST NewBase only.
# 26 batches of 20, one of 5; all CRM updates have independent backread.
# No retries of uncertain REST writes, no CRM adds/deletes, no scheduled recurrence.
param([string]$ExpectedComputerName='SRV',[int]$BatchSize=20,[int]$MaxBatches=27)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root
$status=Join-Path $root 'state\msp-bitrix-unnamed-name-drain-v1.status'
$journal=Join-Path $root 'state\msp-bitrix-unnamed-name-drain-v1.journal'
$backup=Join-Path $root 'data\customers.before-unnamed-name-drain-v1.sqlite.bak'
$prev=Join-Path $root 'state\msp-bitrix-unnamed-fix-batch20-v1.status'
$phase='PRECHECK';$batches=0;$verified=0;$posted=0
$locked=$false;$mutex=$null;$items=$null;$start=[DateTime]::UtcNow
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Yes,[string]$Reason){if(-not $Yes){Fail $Reason}}
function CheckFile([string]$Path){
 Need ([IO.File]::Exists($Path)) 'COMPONENT_MISSING'
 Need (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
}
function ReadDb([string]$SQL){
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $root 'bin\sqlite3.exe'
 $i.Arguments='-readonly -batch -bail "'+(Join-Path $root 'data\customers.db')+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'READ_SQLITE_START'}
  $p.StandardInput.WriteLine($SQL);$p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'READ_SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 22000 -or $err.Trim().Length -gt 0 -or $out.Length -gt 22000){Fail 'READ_SQLITE_FAILED'}
  return $out
 }finally{$p.Close()}
}
function Counts(){
 return (ReadDb "SELECT count(*)||':'||coalesce(sum(state='DONE'),0)||':'||coalesce(sum(state='PENDING'),0)||':'||coalesce(sum(state='INTENT'),0)||':'||coalesce(sum(state='UNCERTAIN'),0) FROM msp_bitrix_name_fix;")
}
function Save([string]$Msg){
 [IO.File]::WriteAllText($status,('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';'+$Msg),[Text.Encoding]::ASCII)
}
function Cards([object[]]$Items){
 $commands=New-Object Collections.ArrayList
 foreach($item in $Items){[void]$commands.Add('crm.item.get?entityTypeId=3&id='+$item.crm)}
 for($attempt=1;$attempt -le 3;$attempt++){
  try{return (Batch @($commands.ToArray()))}
  catch{
   if(@('NEWBASE_CURL_FAILED','NEWBASE_HTTP_429','NEWBASE_HTTP_503') -notcontains $_.Exception.Message -or $attempt -eq 3){throw}
   Start-Sleep -Seconds (2*$attempt)
  }
 }
 Fail 'GET_EXHAUSTED'
}
function CardCheck([string]$Reply,[int]$Index,[object]$Item,[bool]$After,[string]$ExpectedFM,[string]$ExpectedComments){
 $p='$.result.result.k'+$Index+'.item';$j="'"+$p+"'"
 $ep="'$.result.result_error.k"+$Index+"'"
 $hex=if($After){$Item.nameHex}else{$Item.oldHex}
 $q="SELECT CASE WHEN json_valid(doc)<>1 THEN 'BAD_JSON' WHEN json_type(doc,"+$ep+") IS NOT NULL THEN 'REST_ERROR' WHEN coalesce(json_type(doc,"+$j+"),'missing')<>'object' THEN 'CARD_MISSING' WHEN coalesce(CAST(json_extract(doc,'"+$p+".id') AS TEXT),'')<>'"+$Item.crm+"' THEN 'ID_CHANGED' WHEN coalesce(json_extract(doc,'"+$p+".originId'),'')<>'"+$Item.guid+"' OR coalesce(json_extract(doc,'"+$p+".originatorId'),'')<>'MSP_ONEC_NEWBASE' THEN 'ORIGIN_CHANGED' WHEN coalesce(json_type(doc,'"+$p+".fm'),'missing')<>'array' THEN 'FM_MISSING' WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".name'),'') AS BLOB))<>'"+$hex+"' THEN 'NAME_MISMATCH' WHEN length(trim(coalesce(json_extract(doc,'"+$p+".lastName'),'')))+length(trim(coalesce(json_extract(doc,'"+$p+".secondName'),'')))>0 THEN 'FIO_CHANGED'"
 if($After){
  $q+=" WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".fm'),'') AS BLOB))<>'"+$ExpectedFM+"' THEN 'FM_CHANGED'"
  $q+=" WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".comments'),'') AS BLOB))<>'"+$ExpectedComments+"' THEN 'COMMENTS_CHANGED'"
 }
 $q+=" ELSE 'PASS' END FROM j;"
 return (SqlJson $Reply $q)
}
function GetHex([string]$Reply,[int]$Index,[string]$Field){
 $p="'$.result.result.k"+$Index+".item."+$Field+"'"
 return (SqlJson $Reply ("SELECT hex(CAST(coalesce(json_extract(doc,"+$p+"),'') AS BLOB)) FROM j;"))
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'HOST_INVALID'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 Need ($BatchSize -eq 20 -and $MaxBatches -eq 27) 'BOUNDS_INVALID'
 Need (-not [IO.File]::Exists($status) -and -not [IO.File]::Exists($journal) -and -not [IO.File]::Exists($backup)) 'ALREADY_ATTEMPTED'
 foreach($f in @($prev,(Join-Path $root 'data\customers.db'),(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'bin\curl.exe'),(Join-Path $root 'config\curl-ca-bundle.crt'),(Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1'),(Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'))){CheckFile $f}
 $proof=[IO.File]::ReadAllText($prev,[Text.Encoding]::ASCII).Trim()
 Need ($proof -match '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;MODE=Batch;POST_BATCHES=1;VERIFIED=20;CRM_WRITES=20;DONE=21;PENDING=525;UNCERTAIN=0;INTENT=0;BACKREAD=PASS;PHONE_EMAIL_PRESERVED=PASS;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0$') 'BATCH20_NOT_ACCEPTED'
 $mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspBitrixNameRepairV1')
 Need ($mutex.WaitOne(0,$false)) 'REPAIR_CONCURRENT';$locked=$true
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_INTEGRITY'
 Need ((Counts) -eq '546:21:525:0:0') 'QUEUE_STATE_CHANGED'
 $criteria="c.buyer=1 AND c.invalid=0 AND c.deletion_mark=0 AND c.onec_type='PERSON' AND length(trim(coalesce(c.person_name,'')))=0 AND length(trim(coalesce(c.name_full,'')))=0 AND length(trim(coalesce(c.name_short,'')))>0"
 $map="SELECT count(*) FROM msp_bitrix_name_fix f JOIN customers c ON c.onec_guid=f.onec_guid JOIN msp_initial_map m ON m.onec_guid=f.onec_guid AND m.crm_id=f.crm_id AND m.entity_kind=3 WHERE "+$criteria+";"
 Need ((ReadDb $map) -eq '546') 'SOURCE_MAPPING_CHANGED'
 $phase='BACKUP'
 $null=Query (".backup '"+($backup.Replace('\','/'))+"'")
 CheckFile $backup
 Need ((ReadDb "ATTACH DATABASE 'file:C:/ProgramData/MspCustomerStore/data/customers.before-unnamed-name-drain-v1.sqlite.bak?mode=ro' AS snap;PRAGMA snap.quick_check;") -eq 'ok') 'BACKUP_VERIFY_FAILED'
 $phase='PREPARED';Secret
 Save 'STATUS=RUNNING;MODE=ONESHOT;SOURCE=TEST_NEWBASE;BATCHES=0;VERIFIED=0;DONE=21;PENDING=525;INTENT=0;UNCERTAIN=0;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 [IO.File]::WriteAllText($journal,'MODE=ONESHOT;SOURCE=TEST_NEWBASE;BEGIN_DONE=21;BEGIN_PENDING=525;PII_EXPORTED=0'+[Environment]::NewLine,[Text.Encoding]::ASCII)
 $done=21;$pending=525
 while($pending -gt 0){
  $phase='BATCH_'+($batches+1)
  Need ($batches -lt $MaxBatches) 'BATCH_LIMIT_REACHED'
  Need (([DateTime]::UtcNow-$start).TotalSeconds -lt 10800) 'TIME_BUDGET_REACHED'
  Need ((Counts) -eq ('546:'+$done+':'+$pending+':0:0')) 'QUEUE_MODIFIED_EXTERNALLY'
  $take=[Math]::Min($BatchSize,$pending)
  $phase='SELECT_CANDIDATES'
  $raw=ReadDb ("SELECT f.onec_guid||'|'||f.crm_id||'|'||hex(CAST(c.name_short AS BLOB)) FROM msp_bitrix_name_fix f JOIN customers c ON c.onec_guid=f.onec_guid JOIN msp_initial_map m ON m.onec_guid=f.onec_guid AND m.crm_id=f.crm_id AND m.entity_kind=3 WHERE f.state='PENDING' AND "+$criteria+" ORDER BY f.onec_guid LIMIT "+$take+";")
  $rows=@($raw -split '\r?\n')
  Need ($rows.Count -eq $take) 'CANDIDATE_COUNT_MISMATCH'
  $items=New-Object Collections.ArrayList
  foreach($row in $rows){
   $v=$row.Split('|')
   Need ($v.Count -eq 3 -and $v[0] -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$' -and $v[1] -match '^[1-9][0-9]{0,9}$' -and $v[2] -match '^(?:[0-9A-F]{2}){1,1024}$') 'SOURCE_ROW_INVALID'
   $name=Unhex $v[2]
   Need ($name.Trim().Length -gt 0 -and $name.Length -le 240) 'NAME_SOURCE_INVALID'
   [void]$items.Add((New-Object PSObject -Property @{guid=$v[0];crm=$v[1];name=$name;nameHex=$v[2];oldHex=(HexUtf8 ('[1C UNNAMED] '+$v[0]));fm='';comments=''}))
  }
  $phase='CRM_PREFLIGHT'
  $before=Cards @($items.ToArray())
  for($i=0;$i -lt $items.Count;$i++){
   $it=$items[$i]
   Need ((CardCheck $before $i $it $false '' '') -eq 'PASS') 'PREFLIGHT_CARD_MISMATCH'
   $it.fm=GetHex $before $i 'fm'
   $it.comments=GetHex $before $i 'comments'
   Need ($it.fm.Length -gt 0 -and $it.fm.Length -le 1024 -and $it.comments.Length -le 1024) 'PREIMAGE_LENGTH_INVALID'
  }
  $phase='PERSIST_INTENT'
  $sql='BEGIN IMMEDIATE;'
  foreach($it in $items){
   $sql+="UPDATE msp_bitrix_name_fix SET state='INTENT',updated_utc=datetime('now') WHERE onec_guid='"+$it.guid+"' AND crm_id="+$it.crm+" AND state='PENDING';"
   $sql+="CREATE TEMP TABLE IF NOT EXISTS _one(n INTEGER CHECK(n=1));INSERT INTO _one SELECT changes();DELETE FROM _one;"
  }
  $sql+='COMMIT;'
  $null=Query $sql
  Need ((Counts) -eq ('546:'+$done+':'+($pending-$take)+':'+$take+':0')) 'INTENT_NOT_DURABLE'
  $phase='CRM_WRITE_ONCE'
  $cmds=New-Object Collections.ArrayList
  foreach($it in $items){[void]$cmds.Add('crm.item.update?entityTypeId=3&id='+$it.crm+'&fields[name]='+(Url $it.name))}
  $posted++;$reply=Batch @($cmds.ToArray()) # One REST POST; do not retry after ambiguous response.
  $phase='CRM_INDEPENDENT_BACKREAD'
  $after=Cards @($items.ToArray())
  for($i=0;$i -lt $items.Count;$i++){
   $it=$items[$i]
   Need ((CardCheck $after $i $it $true $it.fm $it.comments) -eq 'PASS') 'BACKREAD_MISMATCH'
   $sql="BEGIN IMMEDIATE;UPDATE msp_bitrix_name_fix SET state='DONE',updated_utc=datetime('now'),verified_utc=datetime('now') WHERE onec_guid='"+$it.guid+"' AND crm_id="+$it.crm+" AND state='INTENT';CREATE TEMP TABLE _one(n INTEGER CHECK(n=1));INSERT INTO _one SELECT changes();COMMIT;"
   $null=Query $sql
   $verified++
  }
  $done+=$take;$pending-=$take;$batches++
  $items=$null;$before=$null;$after=$null;$reply=$null;$cmds=$null
  Need ((Counts) -eq ('546:'+$done+':'+$pending+':0:0')) 'BATCH_FINAL_COUNTS_BAD'
  [IO.File]::AppendAllText($journal,('BATCH='+$batches+';VERIFIED='+$take+';DONE='+$done+';PENDING='+$pending+';INTENT=0;UNCERTAIN=0;BACKREAD=PASS'+[Environment]::NewLine),[Text.Encoding]::ASCII)
  Save ('STATUS=RUNNING;MODE=ONESHOT;BATCHES='+$batches+';VERIFIED='+$verified+';DONE='+$done+';PENDING='+$pending+';INTENT=0;UNCERTAIN=0;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0')
  Start-Sleep -Milliseconds 1700
 }
 $phase='FINAL'
 Need ($batches -eq 27 -and $verified -eq 525 -and $posted -eq 27) 'EXPECTED_BATCH_TOTALS_MISSING'
 Need ((Counts) -eq '546:546:0:0:0') 'FINAL_QUEUE_NOT_EMPTY'
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'FINAL_DB_INTEGRITY'
 $elapsed=[int]([DateTime]::UtcNow-$start).TotalSeconds
 $msg='STATUS=PASS;MODE=ONESHOT;SOURCE=TEST_NEWBASE;BATCHES=27;VERIFIED=525;CRM_WRITES=525;DONE=546;PENDING=0;INTENT=0;UNCERTAIN=0;BACKREAD=PASS;PHONE_EMAIL_PRESERVED=PASS;SQLITE_QUICK_CHECK=OK;ELAPSED_SECONDS='+$elapsed+';ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 Save $msg
 [IO.File]::AppendAllText($journal,('FINAL='+$msg+[Environment]::NewLine),[Text.Encoding]::ASCII)
 Get-Content $status
 'RESULT=PASS;STAGE=MSP_BITRIX_UNNAMED_NAME_DRAIN_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 # Quarantine every INTENT row; do not resubmit uncertain batches.
 try{$null=Query "UPDATE msp_bitrix_name_fix SET state='UNCERTAIN',updated_utc=datetime('now') WHERE state='INTENT';"}catch{}
 $counts='UNKNOWN';try{$counts=Counts}catch{}
 try{Save ('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';BATCHES_COMPLETED='+$batches+';VERIFIED='+$verified+';QUEUE='+$counts+';REST_POST_ATTEMPTS='+$posted+';ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0')}catch{}
 'RESULT=FAIL;STAGE=MSP_BITRIX_UNNAMED_NAME_DRAIN_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}finally{
 if($locked){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Close()}
 $script:base=$null;$items=$null;$before=$null;$after=$null;$reply=$null
}

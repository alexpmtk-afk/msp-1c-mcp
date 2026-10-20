#requires -version 2
# Single manually launched batch to repair up to 20 existing mapped Bitrix24 contact display names.
# TEST NewBase SRV LOCAL SERVICE only. Never add/delete cards; never retry uncertain CRM writes.
param([string]$ExpectedComputerName='SRV',[int]$MaxCards=20)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root
$phase='PRECHECK';$intentCount=0;$verified=0;$posted=0;$mutex=$null;$locked=$false
$status=Join-Path $root 'state\msp-bitrix-unnamed-fix-batch20-v1.status'
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Ok,[string]$Reason){if(-not $Ok){Fail $Reason}}
function LocalRead([string]$SQL){
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $root 'bin\sqlite3.exe'
 $i.Arguments='-readonly -batch -bail "'+(Join-Path $root 'data\customers.db')+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'SQLITE_READ_START'}
  $p.StandardInput.WriteLine($SQL);$p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'SQLITE_READ_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $out.Length -gt 22000){Fail 'SQLITE_READ_ERROR'}
  return $out
 }finally{$p.Close()}
}
function ReadCards([object[]]$Items){
 $cmds=New-Object Collections.ArrayList
 foreach($item in $Items){[void]$cmds.Add('crm.item.get?entityTypeId=3&id='+$item.crm)}
 # Idempotent GET may be retried; CRM updates must never be retried.
 for($attempt=1;$attempt -le 3;$attempt++){
  try{return (Batch @($cmds.ToArray()))}
  catch{
   if(@('NEWBASE_CURL_FAILED','NEWBASE_HTTP_429','NEWBASE_HTTP_503') -notcontains $_.Exception.Message -or $attempt -eq 3){throw}
   Start-Sleep -Seconds (2*$attempt)
  }
 }
 Fail 'READ_RETRY_EXHAUSTED'
}
function CardCheck([string]$Reply,[int]$Index,[object]$Item,[bool]$After,[string]$ExpectedFM,[string]$ExpectedComments){
 $p='$.result.result.k'+$Index+'.item';$j="'"+$p+"'"
 $ep="'$.result.result_error.k"+$Index+"'"
 $nameHex=if($After){$Item.nameHex}else{$Item.oldHex}
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'BAD_JSON' WHEN json_type(doc,"+$ep+") IS NOT NULL THEN 'REST_ERROR' WHEN coalesce(json_type(doc,"+$j+"),'missing')<>'object' THEN 'MISSING' WHEN coalesce(CAST(json_extract(doc,'"+$p+".id') AS TEXT),'')<>'"+$Item.crm+"' THEN 'ID_CHANGED' WHEN coalesce(json_extract(doc,'"+$p+".originId'),'')<>'"+$Item.guid+"' OR coalesce(json_extract(doc,'"+$p+".originatorId'),'')<>'MSP_ONEC_NEWBASE' THEN 'ORIGIN_CHANGED' WHEN coalesce(json_type(doc,'"+$p+".fm'),'missing')<>'array' THEN 'FM_MISSING' WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".name'),'') AS BLOB))<>'"+$nameHex+"' THEN 'NAME_MISMATCH' WHEN length(trim(coalesce(json_extract(doc,'"+$p+".lastName'),'')))+length(trim(coalesce(json_extract(doc,'"+$p+".secondName'),'')))>0 THEN 'FIO_PARTS_CHANGED'"
 if($After){
  $sql+=" WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".fm'),'') AS BLOB))<>'"+$ExpectedFM+"' THEN 'CONTACT_FIELDS_CHANGED'"
  $sql+=" WHEN hex(CAST(coalesce(json_extract(doc,'"+$p+".comments'),'') AS BLOB))<>'"+$ExpectedComments+"' THEN 'COMMENTS_CHANGED'"
 }
 $sql+=" ELSE 'PASS' END FROM j;"
 return (SqlJson $Reply $sql)
}
function GetHex([string]$Reply,[int]$Index,[string]$Property){
 $p="'$.result.result.k"+$Index+".item."+$Property+"'"
 return (SqlJson $Reply ("SELECT hex(CAST(coalesce(json_extract(doc,"+$p+"),'') AS BLOB)) FROM j;"))
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'HOST_DENIED'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 Need ($MaxCards -eq 20) 'BATCH_SIZE_DENIED'
 Need (-not [IO.File]::Exists($status)) 'PREVIOUS_BATCH_ATTEMPT'
 $pilot=Join-Path $root 'state\msp-bitrix-unnamed-fix-pilot-v1.status'
 Need ([IO.File]::Exists($pilot)) 'PILOT_RECEIPT_MISSING'
 $proof=[IO.File]::ReadAllText($pilot,[Text.Encoding]::ASCII).Trim()
 Need ($proof -match '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;MODE=Pilot;TARGET=546;VERIFIED=1;PENDING=545;UNCERTAIN=0;CRM_WRITES=1;BACKREAD=PASS;NAME_SOURCE=name_short;PHONE_EMAIL_PRESERVED=PASS;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0$') 'PILOT_NOT_ACCEPTED'
 foreach($rel in @('data\customers.db','bin\sqlite3.exe','bin\curl.exe','config\curl-ca-bundle.crt','bin\msp-newbase-bitrix-core-v2.ps1','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi')){
  $f=Join-Path $root $rel
  Need ([IO.File]::Exists($f)) 'REQUIRED_INPUT_MISSING'
  Need (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 }
 $mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspBitrixNameRepairV1')
 Need ($mutex.WaitOne(0,$false)) 'REPAIR_CONCURRENT';$locked=$true
 Need ((LocalRead 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_INTEGRITY'
 $beforeCounts=LocalRead "SELECT count(*)||':'||sum(state='DONE')||':'||sum(state='PENDING')||':'||sum(state='INTENT')||':'||sum(state='UNCERTAIN') FROM msp_bitrix_name_fix;"
 Need ($beforeCounts -eq '546:1:545:0:0') 'QUEUE_NOT_PRISTINE'
 $phase='READ_LOCAL_CANDIDATES'
 $criteria="c.buyer=1 AND c.invalid=0 AND c.deletion_mark=0 AND c.onec_type='PERSON' AND length(trim(coalesce(c.person_name,'')))=0 AND length(trim(coalesce(c.name_full,'')))=0 AND length(trim(coalesce(c.name_short,'')))>0"
 $raw=LocalRead ("SELECT f.onec_guid||'|'||f.crm_id||'|'||hex(CAST(c.name_short AS BLOB)) FROM msp_bitrix_name_fix f JOIN customers c ON c.onec_guid=f.onec_guid JOIN msp_initial_map m ON m.onec_guid=f.onec_guid AND m.crm_id=f.crm_id AND m.entity_kind=3 WHERE f.state='PENDING' AND "+$criteria+" ORDER BY f.onec_guid LIMIT 20;")
 $lines=@($raw -split '\r?\n')
 Need ($lines.Count -eq 20) 'EXPECTED_20_NOT_FOUND'
 $items=New-Object Collections.ArrayList
 foreach($line in $lines){
  $v=$line.Split('|')
  Need ($v.Count -eq 3 -and $v[0] -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$' -and $v[1] -match '^[1-9][0-9]{0,9}$' -and $v[2] -match '^(?:[0-9A-F]{2}){1,1024}$') 'LOCAL_ROW_SHAPE'
  $name=Unhex $v[2]
  Need ($name.Trim().Length -gt 0 -and $name.Length -le 240) 'SOURCE_NAME_INVALID'
  [void]$items.Add((New-Object PSObject -Property @{guid=$v[0];crm=$v[1];name=$name;nameHex=$v[2];oldHex=(HexUtf8 ('[1C UNNAMED] '+$v[0]));fm='';comments=''}))
 }
 $phase='CRM_PREFLIGHT';Secret
 $before=ReadCards @($items.ToArray())
 for($i=0;$i -lt $items.Count;$i++){
  $item=$items[$i]
  Need ((CardCheck $before $i $item $false '' '') -eq 'PASS') 'CRM_BEFORE_MISMATCH'
  $item.fm=GetHex $before $i 'fm'
  $item.comments=GetHex $before $i 'comments'
  Need ($item.fm.Length -gt 0 -and $item.fm.Length -le 1024 -and $item.comments.Length -le 1024) 'PREIMAGE_TOO_LARGE'
 }
 $phase='PERSIST_INTENT'
 $sql='BEGIN IMMEDIATE;'
 foreach($item in $items){
  $sql+="UPDATE msp_bitrix_name_fix SET state='INTENT',updated_utc=datetime('now') WHERE onec_guid='"+$item.guid+"' AND crm_id="+$item.crm+" AND state='PENDING';"
  $sql+="CREATE TEMP TABLE IF NOT EXISTS _changes(n INTEGER CHECK(n=1));INSERT INTO _changes SELECT changes();DELETE FROM _changes;"
 }
 $sql+='COMMIT;'
 $null=Query $sql;$intentCount=20
 $phase='CRM_WRITE_ONCE'
 $cmds=New-Object Collections.ArrayList
 foreach($item in $items){[void]$cmds.Add('crm.item.update?entityTypeId=3&id='+$item.crm+'&fields[name]='+(Url $item.name))}
 $posted=1
 $writeReply=Batch @($cmds.ToArray()) # Exactly one REST write batch. NEVER RETRY POST.
 $phase='CRM_INDEPENDENT_BACKREAD'
 $after=ReadCards @($items.ToArray())
 for($i=0;$i -lt $items.Count;$i++){
  $item=$items[$i]
  Need ((CardCheck $after $i $item $true $item.fm $item.comments) -eq 'PASS') 'CRM_AFTER_MISMATCH'
  $changed=Query ("BEGIN IMMEDIATE;UPDATE msp_bitrix_name_fix SET state='DONE',updated_utc=datetime('now'),verified_utc=datetime('now') WHERE onec_guid='"+$item.guid+"' AND crm_id="+$item.crm+" AND state='INTENT';CREATE TEMP TABLE _one(n INTEGER CHECK(n=1));INSERT INTO _one SELECT changes();COMMIT;")
  $verified++
 }
 $phase='FINAL'
 Need ((LocalRead "SELECT count(*)||':'||sum(state='DONE')||':'||sum(state='PENDING')||':'||sum(state='INTENT')||':'||sum(state='UNCERTAIN') FROM msp_bitrix_name_fix;") -eq '546:21:525:0:0') 'FINAL_COUNTS_BAD'
 Need ((LocalRead 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_QUICK_CHECK_FAILED'
 $receipt='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;MODE=Batch;POST_BATCHES=1;VERIFIED=20;CRM_WRITES=20;DONE=21;PENDING=525;UNCERTAIN=0;INTENT=0;BACKREAD=PASS;PHONE_EMAIL_PRESERVED=PASS;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$receipt,[Text.Encoding]::ASCII)
 $receipt
 'RESULT=PASS;STAGE=MSP_BITRIX_UNNAMED_NAME_BATCH20_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($intentCount -gt 0 -and $null -ne $items){
  # Explicitly quarantine every remaining INTENT: no blind POST replay after an ambiguous response.
  try{
   foreach($item in $items){
    $null=Query ("UPDATE msp_bitrix_name_fix SET state='UNCERTAIN',updated_utc=datetime('now') WHERE onec_guid='"+$item.guid+"' AND state='INTENT';")
   }
  }catch{}
 }
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';POST_BATCHES_ATTEMPTED='+$posted+';VERIFIED='+$verified+';ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=MSP_BITRIX_UNNAMED_NAME_BATCH20_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}finally{
 if($locked){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Close()}
 $script:base=$null;$raw=$null;$before=$null;$after=$null;$writeReply=$null
}

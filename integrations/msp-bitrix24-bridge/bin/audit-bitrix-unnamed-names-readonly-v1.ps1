#requires -version 2
# Read-only audit of 546 historical [1C UNNAMED] candidates in existing SRV customers.db.
# Checks live Bitrix24 mapped contact, current display name, and duplicate origin identities.
# No CRM/OneC/SQLite writes; no customer names, GUIDs, phone, INN or CRM IDs in output.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root
$phase='PRECHECK';$status=Join-Path $root 'state\bitrix-unnamed-names-audit-v1.status'
$done=0;$placeholder=0;$already=0;$other=0;$duplicates=0;$identity=0;$missing=0;$nonemptyParts=0;$batches=0
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function ReadLocal([string]$Statement){
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $root 'bin\sqlite3.exe'
 $i.Arguments='-readonly -batch -bail "'+(Join-Path $root 'data\customers.db')+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'LOCAL_SQLITE_START'}
  $p.StandardInput.WriteLine($Statement);$p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'LOCAL_SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $out.Length -gt 16384){Fail 'LOCAL_SQLITE_BAD'}
  return $out
 }finally{$p.Close()}
}
function Save([string]$Detail){[IO.File]::WriteAllText($status,('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';'+$Detail),[Text.Encoding]::ASCII)}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'HOST_DENIED'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 Need (-not [IO.File]::Exists($status)) 'ALREADY_ATTEMPTED'
 foreach($rel in @('data\customers.db','bin\sqlite3.exe','bin\curl.exe','config\curl-ca-bundle.crt','bin\msp-newbase-bitrix-core-v2.ps1','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi')){
  $f=Join-Path $root $rel
  Need ([IO.File]::Exists($f)) 'REQUIRED_FILE_MISSING'
  Need (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 }
 Need ((ReadLocal 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_NOT_OK'
 $condition="c.buyer=1 AND c.invalid=0 AND c.deletion_mark=0 AND c.onec_type='PERSON' AND length(trim(coalesce(c.person_name,'')))=0 AND length(trim(coalesce(c.name_full,'')))=0 AND length(trim(coalesce(c.name_short,'')))>0"
 $cnt=ReadLocal ("SELECT count(*)||':'||count(m.crm_id)||':'||count(DISTINCT m.crm_id) FROM customers c LEFT JOIN msp_initial_map m ON m.onec_guid=c.onec_guid AND m.entity_kind=3 WHERE "+$condition+";")
 Need ($cnt -eq '546:546:546') 'SOURCE_MAPPING_CHANGED'
 Secret
 $phase='LIVE_CRM_READ'
 $offset=0
 while($offset -lt 546){
  $sql="SELECT c.onec_guid||'|'||m.crm_id||'|'||hex(CAST(c.name_short AS BLOB)) FROM customers c JOIN msp_initial_map m ON m.onec_guid=c.onec_guid WHERE "+$condition+" ORDER BY c.onec_guid LIMIT 10 OFFSET "+$offset+";"
  $raw=ReadLocal $sql
  $lines=@($raw -split '\r?\n')
  Need ($lines.Count -ge 1 -and $lines.Count -le 10) 'LOCAL_BATCH_SHAPE'
  $items=New-Object Collections.ArrayList;$commands=New-Object Collections.ArrayList
  foreach($line in $lines){
   $v=$line.Split('|')
   Need ($v.Count -eq 3 -and $v[0] -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$' -and $v[1] -match '^[1-9][0-9]{0,9}$' -and $v[2] -match '^(?:[0-9A-F]{2}){1,1024}$') 'LOCAL_ROW_INVALID'
   [void]$items.Add((New-Object PSObject -Property @{guid=$v[0];crm=$v[1];namehex=$v[2]}))
   [void]$commands.Add('crm.item.get?entityTypeId=3&id='+$v[1])
   [void]$commands.Add('crm.item.list?entityTypeId=3&filter[originatorId]=MSP_ONEC_NEWBASE&filter[originId]='+$v[0]+'&select[0]=id&start=0')
  }
  $reply=Batch @($commands.ToArray())
  $pieces=New-Object Collections.ArrayList
  for($i=0;$i -lt $items.Count;$i++){
   $it=$items[$i];$gi=2*$i;$li=$gi+1
   $get='$.result.result.k'+$gi+'.item';$list='$.result.result.k'+$li+'.items'
   $g="'"+$get+"'";$l="'"+$list+"'"
   $ge="'$.result.result_error.k"+$gi+"'";$le="'$.result.result_error.k"+$li+"'"
   $placeholderHex=HexUtf8 ('[1C UNNAMED] '+$it.guid)
   $idSql="coalesce(CAST(json_extract(doc,'"+$get+".id') AS TEXT),'')"
   $originSql="coalesce(CAST(json_extract(doc,'"+$get+".originId') AS TEXT),'')"
   $ownerSql="coalesce(CAST(json_extract(doc,'"+$get+".originatorId') AS TEXT),'')"
   $nameSql="hex(CAST(coalesce(json_extract(doc,'"+$get+".name'),'') AS BLOB))"
   $partsSql="length(trim(coalesce(json_extract(doc,'"+$get+".lastName'),'')))+length(trim(coalesce(json_extract(doc,'"+$get+".secondName'),'')))"
   $n="CASE WHEN json_type(doc,"+$ge+") IS NOT NULL THEN 'E' WHEN coalesce(json_type(doc,"+$g+"),'missing')<>'object' THEN 'E' WHEN "+$idSql+"<>'"+$it.crm+"' OR "+$originSql+"<>'"+$it.guid+"' OR "+$ownerSql+"<>'MSP_ONEC_NEWBASE' THEN 'I' WHEN "+$partsSql+">0 THEN 'P' WHEN "+$nameSql+"='"+$placeholderHex+"' THEN 'U' WHEN "+$nameSql+"='"+$it.namehex+"' THEN 'A' ELSE 'O' END"
   $listId="coalesce(CAST(json_extract(doc,'"+$list+"[0].id') AS TEXT),'')"
   $next="'$.result.result_next.k"+$li+"'"
   $m="CASE WHEN json_type(doc,"+$le+") IS NOT NULL OR coalesce(json_type(doc,"+$l+"),'missing')<>'array' THEN 'E' WHEN coalesce(json_type(doc,"+$next+"),'null')<>'null' THEN 'D' WHEN json_array_length(doc,"+$l+")>1 THEN 'D' WHEN json_array_length(doc,"+$l+")=0 THEN 'E' WHEN "+$listId+"<>'"+$it.crm+"' THEN 'I' ELSE 'S' END"
   [void]$pieces.Add('SELECT ('+$n+")||':'||("+$m+') FROM j')
  }
  $states=SqlJson $reply ([string]::Join(' UNION ALL ',[string[]]$pieces.ToArray()))
  $rows=@($states -split '\r?\n')
  Need ($rows.Count -eq $items.Count) 'RESPONSE_CARDINALITY'
  foreach($z in $rows){
   Need ($z -match '^[UIAPOE]:[SEDI]$') 'RESPONSE_INVALID'
   $parts=$z.Split(':')
   switch($parts[0]){'U'{$placeholder++};'A'{$already++};'O'{$other++};'P'{$nonemptyParts++};'I'{$identity++};'E'{$missing++}}
   switch($parts[1]){'D'{$duplicates++};'I'{$identity++};'E'{$missing++}}
   $done++
  }
  $offset+=$items.Count;$batches++
  if(($batches % 10) -eq 0){Save ('STATUS=RUNNING;CHECKED='+$done+';TARGET=546;BATCHES='+$batches+';CRM_WRITES=0;ONEC_WRITES=0;PII_EXPORTED=0')}
  Start-Sleep -Milliseconds 600
 }
 Need ($done -eq 546) 'SCAN_NOT_COMPLETE'
 $phase='FINAL'
 $msg='STATUS=PASS;SOURCE=TEST_NEWBASE;SCANNED=546;PLACEHOLDER='+$placeholder+';ALREADY_NAMED='+$already+';DIFFERENT_NAME='+$other+';OTHER_FIO_PARTS='+$nonemptyParts+';DUPLICATE_ORIGIN='+$duplicates+';IDENTITY_PROBLEMS='+$identity+';CRM_READ_ERRORS='+$missing+';BATCHES='+$batches+';CRM_WRITES=0;ONEC_WRITES=0;SQLITE_WRITES=0;PII_EXPORTED=0'
 Save $msg;Get-Content $status;'RESULT=PASS;STAGE=BITRIX_UNNAMED_NAMES_READONLY_AUDIT_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{Save ('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';CHECKED='+$done+';CRM_WRITES=0;ONEC_WRITES=0;PII_EXPORTED=0')}catch{}
 'RESULT=FAIL;STAGE=BITRIX_UNNAMED_NAMES_READONLY_AUDIT_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}finally{$script:base=$null}

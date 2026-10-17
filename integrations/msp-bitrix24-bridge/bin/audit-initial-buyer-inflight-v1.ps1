#requires -version 2
# LOCAL SERVICE, TEST NewBase, read-only Bitrix24 GET/LIST; only aggregate results.
# Diagnose the current batch of V2 inflight entries without any CRM write.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$script:root=$root
$phase='PRECHECK'
$status=Join-Path $root 'state\bitrix-initial-inflight-readonly-v1.status'
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'msp-newbase-bitrix-core-v2.ps1')
function Require([bool]$Ok,[string]$Gate){if(-not $Ok){Fail $Gate}}
function SqlRead([string]$Sql){
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=Join-Path $root 'bin\sqlite3.exe'
 $psi.Arguments='-readonly -batch -bail "'+(Join-Path $root 'data\customers.db')+'"'
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$psi
 try{
  if(-not $p.Start()){Fail 'SQL_READ_START'}
  $p.StandardInput.WriteLine($Sql);$p.StandardInput.Close()
  $output=$p.StandardOutput.ReadToEnd()
  $errorText=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(20000)){$p.Kill();Fail 'SQL_READ_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $errorText.Trim().Length -gt 0 -or $output.Length -gt 131072){Fail 'SQL_READ_ERROR'}
  return $output.Trim()
 }finally{$p.Close()}
}
function UnhexSafe([string]$H){
 if($H.Length % 2 -ne 0 -or $H.Length -gt 16384 -or $H -notmatch '^[A-F0-9]*$'){Fail 'HEX_INVALID'}
 $b=New-Object byte[] ($H.Length/2)
 for($j=0;$j -lt $b.Length;$j++){$b[$j]=[Convert]::ToByte($H.Substring($j*2,2),16)}
 return [Text.Encoding]::UTF8.GetString($b)
}
function Field([string]$Response,[int]$Index,[string]$Field){
 if(@('id','originId','originatorId','title','name','comments') -notcontains $Field){Fail 'FIELD_DENIED'}
 $path="'$.result.result.k"+$Index+".item."+$Field+"'"
 $expr="CASE WHEN json_type(doc,"+$path+") IS NULL THEN 'MISSING' WHEN json_type(doc,"+$path+")='null' THEN 'NULL' ELSE hex(CAST(json_extract(doc,"+$path+") AS BLOB)) END"
 return BResult $Response $Index $expr
}
try{
 Require ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'HOST_INVALID'
 Require ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Require ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_REQUIRED'
 $v2='C:\ProgramData\MspCustomerStore\state\bitrix-initial-all-buyers-v2.status'
 Require ([IO.File]::Exists($v2)) 'V2_STATUS_MISSING'
 $receipt=[IO.File]::ReadAllText($v2,[Text.Encoding]::ASCII)
 Require ($receipt -match 'STATUS=FAIL;GATE=CRM_DETAILS_BACKREAD_MISMATCH;PHASE=CRM_CREATE_BACKREAD;' -and $receipt -match ';MAPPED=5;TARGET=6433') 'V2_FAILURE_NOT_EXPECTED'
 $counts=SqlRead "SELECT (SELECT count(*) FROM msp_initial_map)||':'||(SELECT count(*) FROM msp_initial_inflight);"
 Require ($counts -match '^5:([1-9][0-9]?)$') 'LOCAL_STATE_NOT_5_PLUS_INFLIGHT'
 $num=[int]$Matches[1]
 Require ($num -le 20) 'UNEXPECTED_BATCH_SIZE'
 $phase='READ_INFLIGHT_SQLITE'
 $sql="SELECT i.onec_guid||'|'||i.crm_type||'|'||c.onec_type||'|'||hex(CAST(coalesce(c.name_short,'') AS BLOB))||'|'||hex(CAST(coalesce(c.name_full,'') AS BLOB))||'|'||hex(CAST(coalesce(c.person_name,'') AS BLOB))||'|'||hex(CAST(coalesce(c.inn,'') AS BLOB)) FROM msp_initial_inflight i JOIN customers c ON c.onec_guid=i.onec_guid ORDER BY i.onec_guid;"
 $rows=SqlRead $sql
 $items=New-Object Collections.ArrayList
 foreach($line in ($rows -split '\r?\n')){
  $v=$line.Split('|')
  Require ($v.Length -eq 7) 'SOURCE_ROW_SHAPE_INVALID'
  Require ($v[0] -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') 'GUID_INVALID'
  Require (@('3','4') -contains $v[1]) 'CRM_TYPE_INVALID'
  Require (@('LEGAL','PERSON','REVIEW') -contains $v[2]) 'SOURCE_TYPE_INVALID'
  $short=UnhexSafe $v[3];$full=UnhexSafe $v[4];$person=UnhexSafe $v[5];$inn=UnhexSafe $v[6]
  $title=if($v[1] -eq '3'){$person}else{$short}
  if($title.Trim().Length -eq 0){$title=if($full.Trim().Length -gt 0){$full}else{'[1C UNNAMED] '+$v[0]}}
  if($v[2] -eq 'REVIEW'){$title='[1C TYPE REVIEW] '+$title}
  if($title.Length -gt 240){$title=$title.Substring(0,240)}
  $details='Source=1C NewBase; Type='+$v[2]
  if($v[1] -eq '4'){
   if($full.Trim().Length -gt 0){$details+='; FullName='+$full}
   if($inn.Trim().Length -gt 0){$details+='; INN='+$inn}
  }else{$details+='; Name='+$title}
  [void]$items.Add((New-Object PSObject -Property @{guid=$v[0];kind=[int]$v[1];title=$title;comments=$details}))
 }
 Require ($items.Count -eq $num) 'INFLIGHT_COUNT_MISMATCH'
 $phase='BITRIX_READONLY'
 Secret
 $look=New-Object Collections.ArrayList
 foreach($it in $items){
  [void]$look.Add(('crm.item.list?entityTypeId='+$it.kind+'&filter[originatorId]=MSP_ONEC_NEWBASE&filter[originId]='+$it.guid+'&select[0]=id&start=0'))
 }
 $r=Batch @($look.ToArray())
 $ids=New-Object Collections.ArrayList
 $notFound=0;$ambiguous=0
 for($i=0;$i -lt $items.Count;$i++){
  $found=VerifyBatchList $r $i '.items'
  if($found -eq 'NONE'){$notFound++;[void]$ids.Add(0)}
  elseif($found -match '^[1-9][0-9]{0,9}$'){[void]$ids.Add([int]$found)}
  else{$ambiguous++;[void]$ids.Add(0)}
 }
 $get=New-Object Collections.ArrayList
 $getIdx=New-Object Collections.ArrayList
 for($i=0;$i -lt $items.Count;$i++){
  if($ids[$i] -gt 0){[void]$get.Add('crm.item.get?entityTypeId='+$items[$i].kind+'&id='+$ids[$i]);[void]$getIdx.Add($i)}
 }
 $identity=0;$nameMatched=0;$commentsExact=0;$commentsNull=0;$commentsDifferent=0;$detailsContained=0
 if($get.Count -gt 0){
  $reply=Batch @($get.ToArray())
  for($k=0;$k -lt $get.Count;$k++){
   $item=$items[$getIdx[$k]]
   if((Field $reply $k 'id') -ne (HexUtf8 ([string]$ids[$getIdx[$k]]))){Fail 'CRM_READBACK_ID_MISMATCH'}
   if((Field $reply $k 'originId') -ne (HexUtf8 $item.guid) -or (Field $reply $k 'originatorId') -ne (HexUtf8 'MSP_ONEC_NEWBASE')){Fail 'CRM_ORIGIN_MISMATCH'}
   $identity++
   $key=if($item.kind -eq 3){'name'}else{'title'}
   if((Field $reply $k $key) -eq (HexUtf8 $item.title)){$nameMatched++}
   $actual=Field $reply $k 'comments'
   if($actual -eq (HexUtf8 $item.comments)){$commentsExact++}
   elseif(@('MISSING','NULL','') -contains $actual){$commentsNull++}
   else{
    $commentsDifferent++
    $text=UnhexSafe $actual
    if($text.Contains($item.comments)){$detailsContained++}
   }
  }
 }
 $msg='STATUS=PASS;SOURCE=TEST_NEWBASE;TOTAL_INFLIGHT='+$num+';IDENTITY_VERIFIED='+$identity+';NOT_FOUND='+$notFound+';AMBIGUOUS='+$ambiguous+';NAME_EXACT='+$nameMatched+';COMMENTS_EXACT='+$commentsExact+';COMMENTS_NULL='+$commentsNull+';COMMENTS_DIFFERENT='+$commentsDifferent+';COMMENTS_CONTAIN_EXPECTED='+$detailsContained+';CRM_WRITES=0;DB_WRITES=0'
 [IO.File]::WriteAllText($status,$msg,[Text.Encoding]::ASCII)
 $msg
 'RESULT=PASS;STAGE=INITIAL_BUYERS_INFLIGHT_READONLY_V1'
}catch{
 $gate='UNCLASSIFIED'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 $msg='STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';CRM_WRITES=0;DB_WRITES=0'
 try{[IO.File]::WriteAllText($status,$msg,[Text.Encoding]::ASCII)}catch{}
 $msg
 'RESULT=FAIL;STAGE=INITIAL_BUYERS_INFLIGHT_READONLY_V1'
 exit 1
}finally{$script:base=$null}

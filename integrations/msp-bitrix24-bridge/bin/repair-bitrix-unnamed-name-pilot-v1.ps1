#requires -version 2
# One-card verified repair of historic [1C UNNAMED] contact on physical SRV.
# Uses unique 1C GUID -> contact CRM ID mapping and local name_short. No create/delete.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$script:root=$root
$status=Join-Path $root 'state\msp-bitrix-unnamed-fix-pilot-v1.status'
$audit=Join-Path $root 'state\bitrix-unnamed-names-audit-v1.status'
$backup=Join-Path $root 'data\customers.before-unnamed-fix-v1.sqlite.bak'
$phase='PRECHECK';$intent=$false;$posted=0;$locked=$false;$mutex=$null;$guid='';$crm=''
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Yes,[string]$Reason){if(-not $Yes){Fail $Reason}}
function Local([string]$SQL){
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $root 'bin\sqlite3.exe'
 $i.Arguments='-readonly -batch -bail "'+(Join-Path $root 'data\customers.db')+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'READ_SQLITE_START'}
  $p.StandardInput.WriteLine($SQL);$p.StandardInput.Close()
  $o=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'READ_SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $o.Length -gt 4096){Fail 'READ_SQLITE_ERROR'}
  return $o
 }finally{$p.Close()}
}
function GetCard([string]$Id){return (Batch @('crm.item.get?entityTypeId=3&id='+$Id))}
function VerifyIdentity([string]$Response,[string]$Id,[string]$Guid){
 $q="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN coalesce(json_type(doc,'$.result.result.k0.item'),'missing')<>'object' THEN 'MISSING' WHEN coalesce(CAST(json_extract(doc,'$.result.result.k0.item.id') AS TEXT),'')<>'"+$Id+"' OR coalesce(json_extract(doc,'$.result.result.k0.item.originId'),'')<>'"+$Guid+"' OR coalesce(json_extract(doc,'$.result.result.k0.item.originatorId'),'')<>'MSP_ONEC_NEWBASE' THEN 'BAD_ORIGIN' WHEN coalesce(json_type(doc,'$.result.result.k0.item.fm'),'missing')<>'array' THEN 'FM_MISSING' ELSE 'PASS' END FROM j;"
 return (SqlJson $Response $q)
}
function GetNameHex([string]$Response){
 return (SqlJson $Response "SELECT hex(CAST(coalesce(json_extract(doc,'$.result.result.k0.item.name'),'') AS BLOB)) FROM j;")
}
function GetFioParts([string]$Response){
 return (SqlJson $Response "SELECT hex(CAST(coalesce(json_extract(doc,'$.result.result.k0.item.lastName'),'')||'|'||coalesce(json_extract(doc,'$.result.result.k0.item.secondName'),'') AS BLOB)) FROM j;")
}
function GetFM([string]$Response){
 return (SqlJson $Response "SELECT hex(CAST(coalesce(json_extract(doc,'$.result.result.k0.item.fm'),'') AS BLOB)) FROM j;")
}
try{
 Need ($ExpectedComputerName -eq 'SRV' -and $env:COMPUTERNAME -eq 'SRV') 'HOST_REQUIRED'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 Need (-not [IO.File]::Exists($status) -and -not [IO.File]::Exists($backup)) 'ALREADY_ATTEMPTED'
 foreach($f in @($audit,(Join-Path $root 'data\customers.db'),(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'))){
  Need ([IO.File]::Exists($f)) 'INPUT_MISSING'
  Need (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 }
 $proof=[IO.File]::ReadAllText($audit,[Text.Encoding]::ASCII).Trim()
 Need ($proof -match '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;SCANNED=546;PLACEHOLDER=546;ALREADY_NAMED=0;DIFFERENT_NAME=0;OTHER_FIO_PARTS=0;DUPLICATE_ORIGIN=0;IDENTITY_PROBLEMS=0;CRM_READ_ERRORS=0;BATCHES=55;CRM_WRITES=0;ONEC_WRITES=0;SQLITE_WRITES=0;PII_EXPORTED=0$') 'AUDIT_NOT_ACCEPTED'
 $mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspBitrixNameRepairV1')
 Need ($mutex.WaitOne(0,$false)) 'REPAIR_CONCURRENT';$locked=$true
 Need ((Local 'PRAGMA quick_check;') -eq 'ok') 'DATABASE_INTEGRITY'
 $criteria="c.buyer=1 AND c.invalid=0 AND c.deletion_mark=0 AND c.onec_type='PERSON' AND length(trim(coalesce(c.person_name,'')))=0 AND length(trim(coalesce(c.name_full,'')))=0 AND length(trim(coalesce(c.name_short,'')))>0"
 $count=Local ("SELECT count(*)||':'||count(m.crm_id)||':'||count(DISTINCT m.crm_id)||':'||(SELECT count(*) FROM sqlite_master WHERE type='table' AND name='msp_bitrix_name_fix') FROM customers c JOIN msp_initial_map m ON m.onec_guid=c.onec_guid AND m.entity_kind=3 WHERE "+$criteria+";")
 Need ($count -eq '546:546:546:0') 'MAPPING_CHANGED'
 $phase='BACKUP'
 $null=Query (".backup '"+($backup.Replace('\','/'))+"'")
 Need ([IO.File]::Exists($backup)) 'BACKUP_MISSING'
 Need ((Local "ATTACH DATABASE 'file:C:/ProgramData/MspCustomerStore/data/customers.before-unnamed-fix-v1.sqlite.bak?mode=ro' AS old;PRAGMA old.quick_check;") -eq 'ok') 'BACKUP_CORRUPT'
 $phase='INITIALIZE_QUEUE'
 $sql="PRAGMA foreign_keys=ON;BEGIN IMMEDIATE;"+
 "CREATE TABLE msp_bitrix_name_fix(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('PENDING','INTENT','DONE','UNCERTAIN')),updated_utc TEXT NOT NULL,verified_utc TEXT,FOREIGN KEY(onec_guid) REFERENCES customers(onec_guid));"+
 "INSERT INTO msp_bitrix_name_fix(onec_guid,crm_id,state,updated_utc) SELECT c.onec_guid,m.crm_id,'PENDING',datetime('now') FROM customers c JOIN msp_initial_map m ON m.onec_guid=c.onec_guid AND m.entity_kind=3 WHERE "+$criteria+";"+
 "CREATE UNIQUE INDEX idx_msp_bitrix_name_fix_crm ON msp_bitrix_name_fix(crm_id);"+
 "CREATE TEMP TABLE _assert(n INTEGER CHECK(n=546));INSERT INTO _assert SELECT count(*) FROM msp_bitrix_name_fix;COMMIT;"
 $null=Query $sql
 Need ((Local 'SELECT count(*) FROM msp_bitrix_name_fix;') -eq '546') 'QUEUE_BAD'
 $phase='SELECT_PILOT'
 $row=Local ("SELECT f.onec_guid||'|'||f.crm_id||'|'||hex(CAST(c.name_short AS BLOB)) FROM msp_bitrix_name_fix f JOIN customers c ON c.onec_guid=f.onec_guid WHERE f.state='PENDING' ORDER BY f.onec_guid LIMIT 1;")
 $v=$row.Split('|')
 Need ($v.Length -eq 3 -and $v[0] -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$' -and $v[1] -match '^[1-9][0-9]{0,9}$' -and $v[2] -match '^(?:[0-9A-F]{2}){1,1024}$') 'PILOT_ROW_INVALID'
 $guid=$v[0];$crm=$v[1];$name=Unhex $v[2]
 Need ($name.Trim().Length -gt 0 -and $name.Length -le 240) 'SOURCE_NAME_INVALID'
 $phase='CRM_PREFLIGHT';Secret
 $before=GetCard $crm
 Need ((VerifyIdentity $before $crm $guid) -eq 'PASS') 'ORIGIN_NOT_VERIFIED'
 Need ((GetNameHex $before) -eq (HexUtf8 ('[1C UNNAMED] '+$guid))) 'TITLE_CHANGED'
 $beforeParts=GetFioParts $before
 Need ($beforeParts -eq (HexUtf8 '|')) 'FIO_PARTS_ALREADY_SET'
 $beforeFM=GetFM $before
 Need ($beforeFM.Length -gt 0) 'FM_READ_FAILED'
 $phase='PERSIST_INTENT'
 $commit="BEGIN IMMEDIATE;UPDATE msp_bitrix_name_fix SET state='INTENT',updated_utc=datetime('now') WHERE onec_guid='"+$guid+"' AND crm_id="+$crm+" AND state='PENDING';CREATE TEMP TABLE _one(n INTEGER CHECK(n=1));INSERT INTO _one SELECT changes();COMMIT;"
 $null=Query $commit;$intent=$true
 $phase='CRM_WRITE_ONCE'
 $command='crm.item.update?entityTypeId=3&id='+$crm+'&fields[name]='+(Url $name)
 $posted=1;$null=Batch @($command)
 $phase='CRM_INDEPENDENT_BACKREAD'
 $after=GetCard $crm
 Need ((VerifyIdentity $after $crm $guid) -eq 'PASS') 'BACKREAD_ORIGIN_CHANGED'
 Need ((GetNameHex $after) -eq (HexUtf8 $name)) 'BACKREAD_NAME_MISMATCH'
 Need ((GetFioParts $after) -eq $beforeParts) 'BACKREAD_FIO_CHANGED'
 Need ((GetFM $after) -eq $beforeFM) 'BACKREAD_CONTACT_FIELDS_CHANGED'
 $phase='COMMIT_DONE'
 $upd="BEGIN IMMEDIATE;UPDATE msp_bitrix_name_fix SET state='DONE',updated_utc=datetime('now'),verified_utc=datetime('now') WHERE onec_guid='"+$guid+"' AND crm_id="+$crm+" AND state='INTENT';CREATE TEMP TABLE _one(n INTEGER CHECK(n=1));INSERT INTO _one SELECT changes();COMMIT;"
 $null=Query $upd;$intent=$false
 $stats=Local "SELECT count(*)||':'||sum(state='DONE')||':'||sum(state='PENDING')||':'||sum(state='INTENT')||':'||sum(state='UNCERTAIN') FROM msp_bitrix_name_fix;"
 Need ($stats -eq '546:1:545:0:0') 'QUEUE_BACKREAD_FAILED'
 Need ((Local 'PRAGMA quick_check;') -eq 'ok') 'FINAL_INTEGRITY'
 $msg='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;MODE=Pilot;TARGET=546;VERIFIED=1;PENDING=545;UNCERTAIN=0;CRM_WRITES=1;BACKREAD=PASS;NAME_SOURCE=name_short;PHONE_EMAIL_PRESERVED=PASS;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$msg,[Text.Encoding]::ASCII)
 $msg;'RESULT=PASS;STAGE=MSP_BITRIX_NAME_FIX_PILOT_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($intent -and $guid -match '^[0-9a-f-]{36}$'){
  try{$null=Query ("UPDATE msp_bitrix_name_fix SET state='UNCERTAIN',updated_utc=datetime('now') WHERE onec_guid='"+$guid+"' AND state='INTENT';")}catch{}
 }
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';POST_ATTEMPTED='+$posted+';ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=MSP_BITRIX_NAME_FIX_PILOT_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}finally{if($locked){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Close()};$script:base=$null}

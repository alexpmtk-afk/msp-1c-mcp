#requires -version 2
# TEST NewBase: repeatable one pending NEW buyer from msp_newbuyer_queue -> Bitrix24.
# Default is READ-ONLY; -Apply requires LOCAL SERVICE plus explicit persistent approval.
# Existing 6433 CRM mappings, production 1C, schedules, and existing customer cards are untouched.
# Durable INTENT/UNCERTAIN prevents blind retries after any ambiguous CRM request.
param([string]$ExpectedComputerName='SRV',[switch]$Apply)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$script:root=$root
$phase='PRECHECK';$intent=$false;$posted=0;$locked=$false;$mt=$null
$guid='';$crmId=0;$kind=0;$status=Join-Path $root 'state\msp-newbuyer-bitrix-auto-v2.status'
$script:base=$null
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function ReadDb([string]$Sql){
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $p=New-Object Diagnostics.Process;$i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=$exe;$i.Arguments='-readonly -batch -bail "'+$db+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p.StartInfo=$i
 try{
  Need ($p.Start()) 'SQLITE_START'
  $p.StandardInput.WriteLine($Sql);$p.StandardInput.Close()
  $result=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(15000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  Need ($p.ExitCode -eq 0 -and $err.Trim().Length -eq 0 -and $result.Length -le 8192) 'SQLITE_READ'
  return $result
 }finally{$p.Close()}
}
function One([string]$Command){return (Batch @($Command))}
function ListCount([string]$Reply){
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN json_type(doc,'$.result.result_error.k0') IS NOT NULL THEN 'REST_ERROR' WHEN json_type(doc,'$.result.result.k0.items')<>'array' THEN 'BAD_SHAPE' WHEN json_type(doc,'$.result.result_next.k0') IS NOT NULL THEN 'PAGING' ELSE CAST(json_array_length(doc,'$.result.result.k0.items') AS TEXT) END FROM j;"
 return (SqlJson $Reply $sql)
}
function ReqCount([string]$Reply){
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN json_type(doc,'$.error') IS NOT NULL THEN 'REST_ERROR' WHEN json_type(doc,'$.result')<>'array' THEN 'BAD_SHAPE' WHEN json_type(doc,'$.next') IS NOT NULL THEN 'PAGING' ELSE CAST(json_array_length(doc,'$.result') AS TEXT) END FROM j;"
 return (SqlJson $Reply $sql)
}
function ResultValue([string]$Reply,[string]$Path){
 Need ($Path -match '^\$\.result\.result\.k0(\.item\.id)?$') 'RESULT_PATH_INVALID'
 $q="SELECT CASE WHEN json_valid(doc)<>1 OR json_type(doc,'$.result.result_error.k0') IS NOT NULL THEN 'INVALID' WHEN json_type(doc,'"+$Path+"') IN ('text','integer') THEN CAST(json_extract(doc,'"+$Path+"') AS TEXT) ELSE 'INVALID' END FROM j;"
 return (SqlJson $Reply $q)
}
function VerifyCrm([int]$Id,[int]$Type,[string]$Guid,[string]$Wanted){
 $v=One ('crm.item.get?entityTypeId='+$Type+'&id='+$Id)
 $field=if($Type -eq 4){'title'}else{'name'}
 $q="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN CAST(json_extract(doc,'$.result.result.k0.item.id') AS TEXT)='"+$Id+"' AND json_extract(doc,'$.result.result.k0.item.originId')='"+$Guid+"' AND json_extract(doc,'$.result.result.k0.item.originatorId')='MSP_ONEC_NEWBASE' AND hex(CAST(coalesce(json_extract(doc,'$.result.result.k0.item."+$field+"'),'') AS BLOB))='"+(HexUtf8 $Wanted)+"' THEN 'PASS' ELSE 'FAIL' END FROM j;"
 Need ((SqlJson $v $q) -eq 'PASS') 'COMPANY_CONTACT_BACKREAD'
}
function VerifyReq([int]$ReqId,[int]$Id,[string]$Inn){
 $r=Http 'crm.requisite.get' ('{"id":'+$ReqId+'}')
 $q="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN CAST(json_extract(doc,'$.result.ID') AS TEXT)='"+$ReqId+"' AND CAST(json_extract(doc,'$.result.ENTITY_ID') AS TEXT)='"+$Id+"' AND CAST(json_extract(doc,'$.result.ENTITY_TYPE_ID') AS TEXT)='4' AND hex(CAST(coalesce(json_extract(doc,'$.result.RQ_INN'),'') AS BLOB))='"+(HexUtf8 $Inn)+"' THEN 'PASS' ELSE 'FAIL' END FROM j;"
 Need ((SqlJson $r $q) -eq 'PASS') 'REQUISITE_BACKREAD'
}
function WriteStatus([string]$Code){
 $s='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS='+$Code+';MODE='+$(if($Apply){'APPLY'}else{'READONLY'})+';POST_ATTEMPTS='+$posted+';ONEC_WRITES=0;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$s,[Text.Encoding]::ASCII)
}
try{
 Need ($env:COMPUTERNAME -eq $ExpectedComputerName -and $ExpectedComputerName -eq 'SRV') 'HOST_INVALID'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 if($Apply){
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'APPLY_LOCAL_SERVICE_ONLY'
 $approval=Join-Path $root 'config\newbuyer-crm-auto-approval.txt'
 Need ([IO.File]::Exists($approval)) 'AUTO_APPLY_NOT_APPROVED'
 Need (([IO.File]::GetAttributes($approval) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'APPROVAL_REPARSE'
 Need ([IO.File]::ReadAllText($approval,[Text.Encoding]::ASCII).Trim() -eq 'ALLOW_NEW_BUYERS=YES;SOURCE=TEST_NEWBASE;MAX_PER_RUN=1') 'AUTO_APPROVAL_INVALID'
}
 foreach($rel in @('data\customers.db','bin\sqlite3.exe','bin\curl.exe','bin\msp-newbase-bitrix-core-v2.ps1','config\curl-ca-bundle.crt','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi','config\collector.ini')){
  $file=Join-Path $root $rel;Need ([IO.File]::Exists($file)) 'COMPONENT_MISSING'
  Need (([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 }
 $config=[IO.File]::ReadAllText((Join-Path $root 'config\collector.ini'))
 foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  Need ($config -match ('(?m)^'+[regex]::Escape($flag)+'\r?$')) 'AUTOMATION_FLAGS_NOT_OFF'
 }
 $mt=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspNewbuyerBitrixAutoV2')
 Need ($mt.WaitOne(0,$false)) 'ALREADY_RUNNING';$locked=$true
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'DB_INTEGRITY'
 $counts=ReadDb "SELECT coalesce(sum(state='PENDING'),0)||':'||coalesce(sum(state IN ('INTENT','UNCERTAIN')),0) FROM msp_newbuyer_queue;"
 Need ($counts -match '^([0-9]+):([0-9]+)$') 'QUEUE_COUNTS_INVALID'
 $pending=[int]$Matches[1];$unresolved=[int]$Matches[2]
 Need ($unresolved -eq 0) 'UNRESOLVED_QUEUE_REVIEW_REQUIRED'
 if($pending -eq 0){
  if($Apply){WriteStatus 'IDLE'}
  'QUEUE_PENDING=0';'CRM_WRITES=0';'ONEC_WRITES=0'
  'RESULT=PASS;STAGE=NEWBUYER_TO_BITRIX_AUTO_V2_IDLE'
  exit 0
 }
 $q="SELECT lower(q.onec_guid)||'|'||q.source_type||'|'||hex(CAST(coalesce(nullif(trim(c.name_short),''),trim(c.name_full),'') AS BLOB))||'|'||hex(CAST(coalesce(trim(c.name_full),'') AS BLOB))||'|'||hex(CAST(coalesce(nullif(trim(c.person_name),''),nullif(trim(c.name_full),''),trim(c.name_short),'') AS BLOB))||'|'||hex(CAST(coalesce(trim(c.inn),'') AS BLOB)) FROM msp_newbuyer_queue q JOIN customers c ON q.onec_guid=c.onec_guid LEFT JOIN msp_initial_map m ON m.onec_guid=q.onec_guid WHERE q.state='PENDING' AND q.crm_id IS NULL AND q.entity_kind IS NULL AND q.source_type=c.onec_type AND q.source_type IN ('LEGAL','PERSON') AND c.buyer=1 AND c.invalid=0 AND c.deletion_mark=0 AND c.needs_review=0 AND m.onec_guid IS NULL ORDER BY q.discovered_utc,q.onec_guid LIMIT 1;"
 $raw=ReadDb $q
 Need ($raw.Length -gt 0 -and $raw.IndexOf([char]10) -lt 0) 'PILOT_SOURCE_INVALID'
 $v=$raw.Split('|');Need ($v.Length -eq 6) 'PILOT_FIELDS_INVALID'
 $guid=$v[0];$sourceType=$v[1]
 Need ($guid -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') 'GUID_INVALID'
 $kind=if($sourceType -eq 'LEGAL'){4}else{3}
 $name=Unhex $v[2];$full=Unhex $v[3];$person=Unhex $v[4];$inn=Unhex $v[5]
 if($kind -eq 4){
  Need ($name.Trim().Length -ge 3 -and $name.Length -le 140) 'LEGAL_NAME_INVALID'
  Need ($full.Trim().Length -ge 3 -and $full.Length -le 240) 'LEGAL_FULL_INVALID'
  Need ($inn -match '^(?:[0-9]{10}|[0-9]{12})$') 'LEGAL_INN_INVALID'
 }else{Need ($person.Trim().Length -ge 2 -and $person.Length -le 160) 'PERSON_NAME_INVALID'}
 $t=ReadDb "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='msp_auto_map';"
 if($t -eq '1'){Need ((ReadDb ("SELECT count(*) FROM msp_auto_map WHERE onec_guid='"+$guid+"';")) -eq '0') 'ALREADY_AUTO_MAPPED'}
 $t=ReadDb "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='msp_auto_ops';"
 if($t -eq '1'){Need ((ReadDb ("SELECT count(*) FROM msp_auto_ops WHERE onec_guid='"+$guid+"';")) -eq '0') 'UNRESOLVED_AUTO_OPERATION'}
 $phase='CRM_DEDUPE_ORIGIN'
 Secret
 $origin=ListCount (One ('crm.item.list?entityTypeId='+$kind+'&filter[originatorId]=MSP_ONEC_NEWBASE&filter[originId]='+$guid+'&select[0]=id&start=0'))
 Need ($origin -eq '0') 'ORIGIN_MATCH_OR_UNCERTAIN'
 if($kind -eq 4){
  $phase='CRM_DEDUPE_TITLE'
  $title=ListCount (One ('crm.item.list?entityTypeId=4&filter[title]='+(Url $name)+'&select[0]=id&start=0'))
  Need ($title -eq '0') 'TITLE_MATCH_OR_UNCERTAIN'
  $phase='CRM_DEDUPE_INN_DIRECT'
  $req=Http 'crm.requisite.list' ('{"filter":{"RQ_INN":'+(JsonQuote $inn)+'},"select":["ID","ENTITY_ID","ENTITY_TYPE_ID"],"start":0}')
  $byInn=ReqCount $req
  Need ($byInn -eq '0') 'INN_MATCH_OR_UNCERTAIN'
 }
 'SOURCE_QUEUE=PASS'
 'ORIGIN_DEDUPE=CLEAR'
 if($kind -eq 4){'TITLE_DEDUPE=CLEAR';'INN_DEDUPE=CLEAR'}
 'CRM_PREFLIGHT=PASS'
 if(-not $Apply){
  'MODE=READONLY';'CRM_WRITES=0';'SQLITE_WRITES=0';'ONEC_WRITES=0'
  'RESULT=PASS;STAGE=NEWBUYER_TO_BITRIX_AUTO_V2_DRYRUN'
  exit 0
 }
 $phase='SQLITE_BACKUP'
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $backup=Join-Path $root ('data\customers.before-newbuyer-bitrix-auto-v2-'+[DateTime]::UtcNow.ToString('yyyyMMdd')+'.sqlite.bak')
 if(-not [IO.File]::Exists($backup)){
  $backupSql=".backup '"+($backup.Replace('\','/'))+"'"
  $null=& $exe -batch -bail $db $backupSql
  Need ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($backup)) 'BACKUP_FAILED'
 }
 Need (([IO.File]::GetAttributes($backup) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'BACKUP_REPARSE'
 $check=@(& $exe -readonly -batch -bail $backup 'PRAGMA quick_check;')
 Need ($LASTEXITCODE -eq 0 -and [string]$check -eq 'ok') 'BACKUP_INTEGRITY'
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'SOURCE_CHANGED_BEFORE_WRITE'
 $phase='PERSIST_INTENT'
 $sql="BEGIN IMMEDIATE;UPDATE msp_newbuyer_queue SET state='INTENT',updated_utc=datetime('now') WHERE onec_guid='"+$guid+"' AND state='PENDING' AND crm_id IS NULL;CREATE TEMP TABLE _assert(n INTEGER NOT NULL CHECK(n=1));INSERT INTO _assert SELECT changes();COMMIT;"
 $null=Query $sql;$intent=$true
 WriteStatus 'INTENT'
 $phase='CRM_CREATE'
 $wanted=if($kind -eq 4){$name}else{$person}
 $field=if($kind -eq 4){'title'}else{'name'}
 $command='crm.item.add?entityTypeId='+$kind+'&fields['+$field+']='+(Url $wanted)+'&fields[originatorId]=MSP_ONEC_NEWBASE&fields[originId]='+$guid
 $posted++;$reply=One $command
 $id=ResultValue $reply '$.result.result.k0.item.id'
 Need ($id -match '^[1-9][0-9]{0,9}$') 'CRM_CREATE_UNCONFIRMED'
 $crmId=[int]$id;WriteStatus 'CREATED_UNVERIFIED'
 $phase='CRM_BACKREAD'
 VerifyCrm $crmId $kind $guid $wanted
 if($kind -eq 4){
  $phase='CRM_REQUISITE_ADD'
  $command='crm.requisite.add?fields[ENTITY_TYPE_ID]=4&fields[ENTITY_ID]='+$crmId+'&fields[PRESET_ID]=1&fields[NAME]='+(Url $name)+'&fields[RQ_COMPANY_NAME]='+(Url $name)+'&fields[RQ_COMPANY_FULL_NAME]='+(Url $full)+'&fields[RQ_INN]='+$inn
  $posted++;$reply=One $command
  $reqId=ResultValue $reply '$.result.result.k0'
  Need ($reqId -match '^[1-9][0-9]{0,9}$') 'REQUISITE_CREATE_UNCONFIRMED'
  $phase='CRM_REQUISITE_BACKREAD'
  VerifyReq ([int]$reqId) $crmId $inn
 }
 $phase='SQLITE_ACK'
 $sql="BEGIN IMMEDIATE;UPDATE msp_newbuyer_queue SET state='DONE',crm_id="+$crmId+",entity_kind="+$kind+",updated_utc=datetime('now') WHERE onec_guid='"+$guid+"' AND state='INTENT';CREATE TEMP TABLE _assert(n INTEGER NOT NULL CHECK(n=1));INSERT INTO _assert SELECT changes();CREATE TABLE IF NOT EXISTS msp_auto_map(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,entity_kind INTEGER NOT NULL,mapped_utc TEXT NOT NULL);INSERT INTO msp_auto_map(onec_guid,crm_id,entity_kind,mapped_utc) VALUES ('"+$guid+"',"+$crmId+","+$kind+",datetime('now')) ON CONFLICT(onec_guid) DO NOTHING;COMMIT;"
 $null=Query $sql;$intent=$false
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'FINAL_DB_INTEGRITY'
 Need ((ReadDb ("SELECT count(*) FROM msp_newbuyer_queue WHERE onec_guid='"+$guid+"' AND state='DONE' AND crm_id="+$crmId+" AND entity_kind="+$kind+";")) -eq '1') 'ACK_NOT_CONFIRMED'
 WriteStatus 'PASS'
 'RESULT=PASS;STAGE=NEWBUYER_TO_BITRIX_AUTO_V2_APPLY'
 'CRM_CREATED=1';'BACKREAD=PASS';'QUEUE_DONE=1'
 'CRM_POST_ATTEMPTS='+$posted;'ONEC_WRITES=0';'PII_EXPORTED=0'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($intent){
  try{$null=Query ("UPDATE msp_newbuyer_queue SET state='UNCERTAIN',updated_utc=datetime('now') WHERE onec_guid='"+$guid+"' AND state='INTENT';")}catch{}
  try{WriteStatus ('UNCERTAIN_'+$gate)}catch{}
 }
 'RESULT=FAIL;STAGE=NEWBUYER_TO_BITRIX_AUTO_V2;PHASE='+$phase+';GATE='+$gate
 'CRM_POST_ATTEMPTS='+$posted;'NO_BLIND_RETRY=YES';'ONEC_WRITES=0';'PII_EXPORTED=0'
 exit 1
}finally{
 if($locked){$mt.ReleaseMutex()}
 if($null -ne $mt){$mt.Close()}
 $script:base=$null
}
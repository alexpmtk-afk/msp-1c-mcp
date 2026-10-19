#requires -version 2
# Prepare durable Bitrix24 PHONE-only delta queue from the already unified SRV SQLite.
# No OData / CRM network requests, no scheduling and no personal data in stdout.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$script:root=$root
$phase='PRECHECK'
$status=Join-Path $root 'state\msp-bitrix-phone-queue-v1.status'
$backup=Join-Path $root 'data\customers.before-phone-queue-v1.sqlite.bak'
. (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function ReadOnly([string]$Statement){
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=Join-Path $root 'bin\sqlite3.exe'
 $info.Arguments='-readonly -batch -bail "'+(Join-Path $root 'data\customers.db')+'"'
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$info
 try{
  if(-not $p.Start()){Fail 'SQLITE_START'}
  $p.StandardInput.WriteLine($Statement);$p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -ne 0){Fail 'SQLITE_QUERY_FAILED'}
  if($out.Length -gt 3000){Fail 'OUTPUT_TOO_LONG'}
  return $out
 }finally{$p.Close()}
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'HOST_INVALID'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 Need (-not [IO.File]::Exists($status) -and -not [IO.File]::Exists($backup)) 'ALREADY_ATTEMPTED'
 foreach($rel in @('data\customers.db','bin\sqlite3.exe','state\customer-unified-phones-v1.status')){
  $p=Join-Path $root $rel
  Need ([IO.File]::Exists($p) -and (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -eq 0)) 'INPUT_NOT_TRUSTED'
 }
 $receipt=[IO.File]::ReadAllText((Join-Path $root 'state\customer-unified-phones-v1.status'),[Text.Encoding]::ASCII).Trim()
 Need ($receipt -match 'STATUS=PASS;SOURCE=TEST_NEWBASE;BUYERS=6433;MAPPED=6433;PHONE_ROWS=4068;PHONE_BUYERS=4067;FORMAT_CANDIDATES=4032;FORMAT_REVIEW=36;BACKUP=VERIFIED;SQLITE_QUICK_CHECK=OK;ONEC_WRITES=0;BITRIX_WRITES=0;AUTO_UPDATE=OFF') 'UNIFIED_SOURCE_NOT_ACCEPTED'
 Need ((ReadOnly 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_INTEGRITY'
 $phase='VERIFY_SOURCE'
 $counts=ReadOnly "SELECT (SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0)||':'||(SELECT count(*) FROM msp_initial_map)||':'||(SELECT count(*) FROM msp_customer_phone)||':'||(SELECT count(DISTINCT onec_guid) FROM msp_customer_phone)||':'||(SELECT sum(format_review) FROM msp_customer_phone)||':'||(SELECT count(*) FROM sqlite_master WHERE name='msp_bitrix_phone_queue');"
 Need ($counts -eq '6433:6433:4068:4067:36:0') 'SOURCE_COUNTS_CHANGED'
 $phase='BACKUP_SOURCE'
 $null=Query (".backup '"+($backup.Replace('\','/'))+"'")
 Need ([IO.File]::Exists($backup)) 'BACKUP_MISSING'
 $backupCheck=ReadOnly "ATTACH DATABASE 'file:C:/ProgramData/MspCustomerStore/data/customers.before-phone-queue-v1.sqlite.bak?mode=ro' AS pre;PRAGMA pre.quick_check;"
 Need ($backupCheck -eq 'ok') 'BACKUP_INTEGRITY'
 $phase='PREPARE_QUEUE'
 $sql="BEGIN IMMEDIATE;"+
 "CREATE TABLE msp_bitrix_phone_queue(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,entity_kind INTEGER NOT NULL,phone_count INTEGER NOT NULL CHECK(phone_count IN (1,2)),state TEXT NOT NULL CHECK(state IN ('PENDING','INTENT','DONE','UNCERTAIN','REVIEW')),created_utc TEXT NOT NULL,updated_utc TEXT NOT NULL,verified_utc TEXT,FOREIGN KEY(onec_guid) REFERENCES customers(onec_guid));"+
 "INSERT INTO msp_bitrix_phone_queue(onec_guid,crm_id,entity_kind,phone_count,state,created_utc,updated_utc) SELECT p.onec_guid,m.crm_id,m.entity_kind,count(*) AS phone_count,'PENDING',datetime('now'),datetime('now') FROM msp_customer_phone p JOIN msp_initial_map m ON m.onec_guid=p.onec_guid JOIN customers c ON c.onec_guid=p.onec_guid WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND m.entity_kind IN (3,4) AND m.crm_id>0 GROUP BY p.onec_guid HAVING sum(p.format_review)=0;"+
 "CREATE INDEX idx_msp_bitrix_phone_queue_state ON msp_bitrix_phone_queue(state,entity_kind,onec_guid);"+
 "CREATE TEMP TABLE _assert(a INTEGER CHECK(a=4031),b INTEGER CHECK(b=4032),c INTEGER CHECK(c=1));"+
 "INSERT INTO _assert SELECT count(*),sum(phone_count),sum(CASE WHEN phone_count=2 THEN 1 ELSE 0 END) FROM msp_bitrix_phone_queue;"+
 "COMMIT;"
 $null=Query $sql
 $phase='BACKREAD'
 Need ((ReadOnly 'PRAGMA quick_check;') -eq 'ok') 'BACKREAD_INTEGRITY'
 $result=ReadOnly "SELECT count(*)||':'||sum(phone_count)||':'||sum(CASE WHEN entity_kind=4 AND phone_count=1 THEN 1 ELSE 0 END)||':'||sum(CASE WHEN entity_kind=3 AND phone_count=1 THEN 1 ELSE 0 END)||':'||sum(CASE WHEN phone_count=2 THEN 1 ELSE 0 END) FROM msp_bitrix_phone_queue;"
 Need ($result -eq '4031:4032:1089:2941:1') 'QUEUE_BACKREAD_MISMATCH'
 $msg='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;QUEUE_BUYERS=4031;QUEUE_PHONE_ROWS=4032;COMPANY_SINGLE=1089;CONTACT_SINGLE=2941;TWO_PHONE_BUYERS=1;REVIEW_EXCLUDED=36;BACKUP=VERIFIED;SQLITE_QUICK_CHECK=OK;CRM_WRITES=0;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$msg,[Text.Encoding]::ASCII)
 $msg
 'RESULT=PASS;STAGE=MSP_BITRIX_PHONE_QUEUE_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBASE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';CRM_WRITES=0;PII_EXPORTED=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=MSP_BITRIX_PHONE_QUEUE_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

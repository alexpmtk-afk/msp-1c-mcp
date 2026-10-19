#requires -version 2
# One-time LOCAL SERVICE staging: merge already confirmed source phones into existing SRV customers.db.
# No 1C requests, no Bitrix API calls, no automatic sync. Never output personal data.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$main=Join-Path $root 'data\customers.db'
$source=Join-Path $root 'data\phone-source-newbase-v1.sqlite'
$exe=Join-Path $root 'bin\sqlite3.exe'
$status=Join-Path $root 'state\customer-unified-phones-v1.status'
$backup=Join-Path $root 'data\customers.before-phone-unify-v1.sqlite.bak'
function Fail([string]$Code){throw ('UNIFY_PHONE_'+$Code)}
function Sql([string]$Database,[string]$Statement,[bool]$Readonly){
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$exe
 $mode=if($Readonly){'-readonly '}else{''}
 $info.Arguments=$mode+'-batch -bail "'+$Database+'"'
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $proc=New-Object Diagnostics.Process;$proc.StartInfo=$info
 try{
  if(-not $proc.Start()){Fail 'SQLITE_PROCESS_START'}
  $proc.StandardInput.WriteLine($Statement);$proc.StandardInput.Close()
  $out=$proc.StandardOutput.ReadToEnd().Trim()
  $err=$proc.StandardError.ReadToEnd()
  if(-not $proc.WaitForExit(120000)){$proc.Kill();Fail 'SQLITE_TIMEOUT'}
  if($proc.ExitCode -ne 0 -or $err.Trim().Length -gt 0){Fail 'SQLITE_COMMAND_FAILED'}
  if($out.Length -gt 2048){Fail 'UNEXPECTED_OUTPUT_LENGTH'}
  return $out
 }finally{$proc.Close()}
}
function FileOK([string]$Path){
 if(-not [IO.File]::Exists($Path)){Fail 'MISSING_INPUT'}
 if(([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DENIED'}
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){Fail 'HOST_INVALID'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_ONLY'}
 if([IO.File]::Exists($status) -or [IO.File]::Exists($backup)){Fail 'ALREADY_ATTEMPTED'}
 foreach($f in @($main,$source,$exe,(Join-Path $root 'state\customer-phone-snapshot-v2.status'))){FileOK $f}
 $snapshot=[IO.File]::ReadAllText((Join-Path $root 'state\customer-phone-snapshot-v2.status'),[Text.Encoding]::ASCII).Trim()
 if($snapshot -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;ACTIVE_BUYERS=6433;CONTACT_ROWS=10751;MATCHED_BUYER_ROWS=9975;OTHER_ROWS=776;PHONE_NUMBER_ROWS=4068;PHONE_WITHOUT_CODES_ROWS=3468;DISPLAY_ROWS=9973;PHONE_TYPE_ROWS=4068;PHONE_CANDIDATE_ROWS=4068;BUYERS_WITH_PHONE=4067;BUYERS_MULTIPLE_PHONES=1;PAGES=108;ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;STAGING_DB_WRITES=YES;PII_EXPORTED=0$'){Fail 'SOURCE_RECEIPT_CHANGED'}
 if((Sql $main 'PRAGMA quick_check;' $true) -ne 'ok'){Fail 'MAIN_DB_NOT_OK'}
 if((Sql $source 'PRAGMA quick_check;' $true) -ne 'ok'){Fail 'PHONE_DB_NOT_OK'}
 $phase='VERIFY_COUNTS_AND_MAPPING'
 $attach="ATTACH DATABASE 'file:C:/ProgramData/MspCustomerStore/data/phone-source-newbase-v1.sqlite?mode=ro' AS ph;"
 $check=$attach+"SELECT (SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0)||':'||(SELECT count(*) FROM msp_initial_map)||':'||(SELECT count(DISTINCT entity_kind||':'||crm_id) FROM msp_initial_map)||':'||(SELECT count(*) FROM ph.phone_source)||':'||(SELECT count(DISTINCT onec_guid) FROM ph.phone_source)||':'||(SELECT count(*) FROM ph.phone_source p LEFT JOIN customers c ON c.onec_guid=p.onec_guid LEFT JOIN msp_initial_map m ON m.onec_guid=p.onec_guid WHERE c.onec_guid IS NULL OR c.buyer<>1 OR c.invalid<>0 OR c.deletion_mark<>0 OR m.onec_guid IS NULL)||':'||(SELECT count(*) FROM sqlite_master WHERE type='table' AND name='msp_customer_phone');"
 if((Sql $main $check $true) -ne '6433:6433:6433:4068:4067:0:0'){Fail 'SOURCE_JOIN_NOT_ACCEPTED'}
 $phase='VERIFY_EXISTING_CUSTOMER_FIELDS'
 $fieldStats="SELECT count(*)||':'||sum(CASE WHEN length(trim(coalesce(inn,'')))>0 THEN 1 ELSE 0 END)||':'||sum(CASE WHEN length(trim(coalesce(name_short,'')))>0 OR length(trim(coalesce(name_full,'')))>0 OR length(trim(coalesce(person_name,'')))>0 THEN 1 ELSE 0 END) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;"
 $beforeFields=Sql $main $fieldStats $true
 if($beforeFields -notmatch '^6433:([1-9][0-9]{0,3}):([1-9][0-9]{0,3}) $phase='BACKUP_MAIN'
 $parent=[IO.Path]::GetDirectoryName($backup)
 if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
 if([IO.File]::Exists($backup)){Fail 'BACKUP_ALREADY_EXISTS'}
 $null=Sql $main (".backup '"+($backup.Replace('\','/'))+"'") $true
 FileOK $backup
 if((Sql $backup 'PRAGMA quick_check;' $true) -ne 'ok'){Fail 'BACKUP_NOT_OK'}
 if((Sql $backup $fieldStats $true) -ne $beforeFields){Fail 'BACKUP_INN_NAME_MISMATCH'}
 $phase='MERGE_PHONE_TABLE'
 $expr='n';foreach($digit in 0..9){$expr="replace($expr,'$digit','')"}
 $digits="length(n)-length($expr)"
 $stmt="PRAGMA foreign_keys=ON;"+$attach+"BEGIN IMMEDIATE;"+
 "CREATE TABLE msp_customer_phone(onec_guid TEXT NOT NULL,line_number INTEGER NOT NULL,phone_number TEXT NOT NULL,source TEXT NOT NULL,format_review INTEGER NOT NULL CHECK(format_review IN (0,1)),PRIMARY KEY(onec_guid,line_number),FOREIGN KEY(onec_guid) REFERENCES customers(onec_guid));"+
 "INSERT INTO msp_customer_phone(onec_guid,line_number,phone_number,source,format_review) WITH p AS (SELECT onec_guid,line_number,trim(phone_number) AS n,phone_number,source FROM ph.phone_source),d AS (SELECT onec_guid,line_number,n,phone_number,source,"+$digits+" AS digits FROM p) SELECT onec_guid,line_number,phone_number,source,CASE WHEN length(n)<=40 AND digits BETWEEN 7 AND 15 AND n NOT GLOB '*[^0-9+() ./-]*' AND n NOT LIKE '_%+%' THEN 0 ELSE 1 END FROM d;"+
 "CREATE INDEX idx_msp_customer_phone_guid ON msp_customer_phone(onec_guid);"+
 "CREATE TEMP TABLE _a(x INTEGER CHECK(x=4068),y INTEGER CHECK(y=4067),z INTEGER CHECK(z=36),w INTEGER CHECK(w=1));"+
 "INSERT INTO _a SELECT count(*),count(DISTINCT onec_guid),sum(format_review),count(*)-count(DISTINCT onec_guid) FROM msp_customer_phone;"+
 "COMMIT;"
 $null=Sql $main $stmt $false
 $phase='BACKREAD_MAIN'
 if((Sql $main 'PRAGMA quick_check;' $true) -ne 'ok'){Fail 'AFTER_MERGE_INTEGRITY'}
 $result=Sql $main "SELECT count(*)||':'||count(DISTINCT onec_guid)||':'||sum(format_review)||':'||sum(CASE WHEN format_review=0 THEN 1 ELSE 0 END) FROM msp_customer_phone;" $true
 if($result -ne '4068:4067:36:4032'){Fail 'BACKREAD_COUNTS_BAD'}
 $phase='BACKREAD_INN_AND_NAMES'
 if((Sql $main $fieldStats $true) -ne $beforeFields){Fail 'INN_NAME_COUNTS_CHANGED'}
 $backupAttach="ATTACH DATABASE 'file:C:/ProgramData/MspCustomerStore/data/customers.before-phone-unify-v1.sqlite.bak?mode=ro' AS before;"
 $exactFields=$backupAttach+"SELECT (SELECT count(*) FROM (SELECT onec_guid,inn,name_short,name_full,person_name FROM customers EXCEPT SELECT onec_guid,inn,name_short,name_full,person_name FROM before.customers))+(SELECT count(*) FROM (SELECT onec_guid,inn,name_short,name_full,person_name FROM before.customers EXCEPT SELECT onec_guid,inn,name_short,name_full,person_name FROM customers));"
 if((Sql $main $exactFields $true) -ne '0'){Fail 'INN_NAME_CONTENT_CHANGED'}
 $proof='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;BUYERS=6433;MAPPED=6433;PHONE_ROWS=4068;PHONE_BUYERS=4067;FORMAT_CANDIDATES=4032;FORMAT_REVIEW=36;INN_PRESENT='+$innPresent+';NAME_PRESENT='+$namePresent+';INN_NAMES_EXACT_BACKREAD=PASS;BACKUP=VERIFIED;SQLITE_QUICK_CHECK=OK;ONEC_WRITES=0;BITRIX_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$proof,[Text.Encoding]::ASCII)
 $proof
 'RESULT=PASS;STAGE=SRV_CUSTOMER_PHONE_UNIFICATION_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^UNIFY_PHONE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';ONEC_WRITES=0;BITRIX_WRITES=0;PII_EXPORTED=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=SRV_CUSTOMER_PHONE_UNIFICATION_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}
){Fail 'INN_OR_NAME_COVERAGE_INVALID'}
 $innPresent=[int]$Matches[1];$namePresent=[int]$Matches[2]
 if($innPresent -gt 6433 -or $namePresent -gt 6433){Fail 'CUSTOMER_FIELD_COUNT_INVALID'}
 $phase='BACKUP_MAIN'
 $parent=[IO.Path]::GetDirectoryName($backup)
 if(-not [IO.Directory]::Exists($parent)){[void][IO.Directory]::CreateDirectory($parent)}
 if([IO.File]::Exists($backup)){Fail 'BACKUP_ALREADY_EXISTS'}
 $null=Sql $main (".backup '"+($backup.Replace('\','/'))+"'") $true
 FileOK $backup
 if((Sql $backup 'PRAGMA quick_check;' $true) -ne 'ok'){Fail 'BACKUP_NOT_OK'}
 $phase='MERGE_PHONE_TABLE'
 $expr='n';foreach($digit in 0..9){$expr="replace($expr,'$digit','')"}
 $digits="length(n)-length($expr)"
 $stmt="PRAGMA foreign_keys=ON;"+$attach+"BEGIN IMMEDIATE;"+
 "CREATE TABLE msp_customer_phone(onec_guid TEXT NOT NULL,line_number INTEGER NOT NULL,phone_number TEXT NOT NULL,source TEXT NOT NULL,format_review INTEGER NOT NULL CHECK(format_review IN (0,1)),PRIMARY KEY(onec_guid,line_number),FOREIGN KEY(onec_guid) REFERENCES customers(onec_guid));"+
 "INSERT INTO msp_customer_phone(onec_guid,line_number,phone_number,source,format_review) WITH p AS (SELECT onec_guid,line_number,trim(phone_number) AS n,phone_number,source FROM ph.phone_source),d AS (SELECT onec_guid,line_number,n,phone_number,source,"+$digits+" AS digits FROM p) SELECT onec_guid,line_number,phone_number,source,CASE WHEN length(n)<=40 AND digits BETWEEN 7 AND 15 AND n NOT GLOB '*[^0-9+() ./-]*' AND n NOT LIKE '_%+%' THEN 0 ELSE 1 END FROM d;"+
 "CREATE INDEX idx_msp_customer_phone_guid ON msp_customer_phone(onec_guid);"+
 "CREATE TEMP TABLE _a(x INTEGER CHECK(x=4068),y INTEGER CHECK(y=4067),z INTEGER CHECK(z=36),w INTEGER CHECK(w=1));"+
 "INSERT INTO _a SELECT count(*),count(DISTINCT onec_guid),sum(format_review),count(*)-count(DISTINCT onec_guid) FROM msp_customer_phone;"+
 "COMMIT;"
 $null=Sql $main $stmt $false
 $phase='BACKREAD_MAIN'
 if((Sql $main 'PRAGMA quick_check;' $true) -ne 'ok'){Fail 'AFTER_MERGE_INTEGRITY'}
 $result=Sql $main "SELECT count(*)||':'||count(DISTINCT onec_guid)||':'||sum(format_review)||':'||sum(CASE WHEN format_review=0 THEN 1 ELSE 0 END) FROM msp_customer_phone;" $true
 if($result -ne '4068:4067:36:4032'){Fail 'BACKREAD_COUNTS_BAD'}
 $proof='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;BUYERS=6433;MAPPED=6433;PHONE_ROWS=4068;PHONE_BUYERS=4067;FORMAT_CANDIDATES=4032;FORMAT_REVIEW=36;BACKUP=VERIFIED;SQLITE_QUICK_CHECK=OK;ONEC_WRITES=0;BITRIX_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$proof,[Text.Encoding]::ASCII)
 $proof
 'RESULT=PASS;STAGE=SRV_CUSTOMER_PHONE_UNIFICATION_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^UNIFY_PHONE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';ONEC_WRITES=0;BITRIX_WRITES=0;PII_EXPORTED=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=SRV_CUSTOMER_PHONE_UNIFICATION_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

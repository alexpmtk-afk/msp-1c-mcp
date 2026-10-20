#requires -version 2
# Offline indexed search backend for Bitrix24, LOCAL SERVICE on SRV only.
# One-time FTS5 trigram index built from already accepted customer snapshot.
# This script changes search index only, never customers or source 1C.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\bitrix-search-index-accepted.txt'
function Fail([string]$Code){throw ('INDEX_'+$Code)}
function Sql([string]$Executable,[string]$Db,[string]$Command){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$Executable
  $psi.Arguments='-batch -bail "'+$Db+'"'
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardInput=$true
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $p=New-Object Diagnostics.Process
  $p.StartInfo=$psi
  try{
    if(-not $p.Start()){Fail 'SQLITE_START_FAILED'}
    $p.StandardInput.Write($Command)
    $p.StandardInput.Close()
    $output=$p.StandardOutput.ReadToEnd()
    $err=$p.StandardError.ReadToEnd()
    if(-not $p.WaitForExit(90000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
    if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0){Fail 'SQLITE_EXECUTION_FAILED'}
    return $output.Trim()
  }finally{$p.Close()}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
  $db=Join-Path $root 'data\customers.db'
  $exe=Join-Path $root 'bin\sqlite3.exe'
  $accept=Join-Path $root 'state\customer-initial-load-accepted.txt'
  $config=Join-Path $root 'config\collector.ini'
  foreach($file in @($db,$exe,$accept,$config)){
    if(-not [IO.File]::Exists($file)){Fail 'FILE_MISSING'}
    if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  }
  if([IO.File]::Exists($status)){Fail 'INDEX_ACCEPTANCE_ALREADY_EXISTS'}
  $receipt=[IO.File]::ReadAllText($accept,[Text.Encoding]::ASCII).Trim()
  if($receipt -notmatch ';ACCEPTANCE=PASS;IDENTITY=LOCAL_SERVICE;ROWS=6433;UNIQUE_GUIDS=6433;ACTIVE=6433;LEGAL=1941;PERSON=4486;REVIEW=6;INITIAL_RUNS=1;DB_INTEGRITY=ok;TEMP_TASK_REMOVED=YES;AUTO_START=OFF;ONEC_WRITES=0;BITRIX_CALLS=0$'){Fail 'S3_NOT_ACCEPTED'}
  $cfg=[IO.File]::ReadAllText($config,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($cfg -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'COLLECTOR_NOT_SAFE_IDLE'}
  }
  $counts=Sql $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;"
  if($counts -ne '6433:6433'){Fail 'SOURCE_ROW_COUNT_INVALID'}
  if((Sql $exe $db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='customer_search_v1';") -ne '0'){Fail 'SEARCH_INDEX_ALREADY_PRESENT'}
  $phase='CREATE_LOCAL_FTS5_INDEX'
  $tx=@'
BEGIN IMMEDIATE;
CREATE VIRTUAL TABLE customer_search_v1 USING fts5(
  onec_guid UNINDEXED,
  name_short,
  name_full,
  person_name,
  inn,
  tokenize='trigram'
);
INSERT INTO customer_search_v1 (onec_guid,name_short,name_full,person_name,inn)
SELECT onec_guid,name_short,name_full,person_name,coalesce(inn,'')
FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;
CREATE TEMP TABLE _search_acceptance (n INTEGER NOT NULL CHECK(n=6433));
INSERT INTO _search_acceptance SELECT count(*) FROM customer_search_v1;
COMMIT;
'@
  $null=Sql $exe $db $tx
  $phase='VERIFY_LOCAL_FTS5'
  $n=Sql $exe $db "SELECT count(*) FROM customer_search_v1;"
  if($n -ne '6433'){Fail 'FTS_COUNT_INVALID'}
  if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DATABASE_INTEGRITY_FAILED'}
  if((Sql $exe $db "SELECT count(*) FROM customers;") -ne '6433'){Fail 'CUSTOMERS_CHANGED'}
  $line='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+
    ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0'
  $fs=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$b=[Text.Encoding]::ASCII.GetBytes($line);$fs.Write($b,0,$b.Length);$fs.Flush()}finally{$fs.Close()}
  'SEARCH_INDEX=customer_search_v1'
  'SEARCH_INDEX_ROWS=6433'
  'CUSTOMERS_UNCHANGED=6433'
  'SEARCH_INDEX_DB_QUICK_CHECK=ok'
  'SEARCH_INDEX_RUN_AS_LOCAL_SERVICE=YES'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_BITRIX_READONLY_INDEX_BUILD'
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^INDEX_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_BITRIX_READONLY_INDEX_BUILD;GATE='+$gate+';PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

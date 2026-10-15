#requires -version 2
# Manual service-account smoke for standalone SRV collector.
# Creates only empty SQLite schema and rolls back one synthetic row.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='IDENTITY'
$statePath=$null
function Fail([string]$Reason){throw ('CUSTOMER_STORE_'+$Reason)}
function Sql([string]$Exe,[string]$Db,[string]$Query){
  $value=@(& $Exe -batch -bail $Db $Query 2>&1)
  if($LASTEXITCODE -ne 0){Fail 'SQLITE_COMMAND_FAILED'}
  return (($value -join [Environment]::NewLine).Trim())
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  if($id.User.Value -ne 'S-1-5-19'){Fail 'NOT_LOCAL_SERVICE'}
  $root='C:\ProgramData\MspCustomerStore'
  $exe=Join-Path $root 'bin\sqlite3.exe'
  $db=Join-Path $root 'data\customers.db'
  $schema=Join-Path $root 'schema\customer-store.sql'
  $conf=Join-Path $root 'config\collector.ini'
  $statePath=Join-Path $root 'state\status.txt'
  foreach($f in @($exe,$schema,$conf)){
    if(-not [IO.File]::Exists($f)){Fail 'REQUIRED_FILE_MISSING'}
    if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  }
  foreach($dir in @('data','state','logs','staging','backups','secrets')){
    $p=Join-Path $root $dir
    if(-not [IO.Directory]::Exists($p)){Fail 'MACHINE_DIRECTORY_MISSING'}
    if(([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DIRECTORY'}
  }
  $text=[IO.File]::ReadAllText($conf,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($text -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'UNSAFE_POLICY'}
  }
  $phase='SQLITE_RUNTIME'
  $v=@(& $exe -version 2>&1)
  if($LASTEXITCODE -ne 0 -or (($v -join ' ') -notmatch '^3\.43\.2(\s|$)')){Fail 'SQLITE_VERSION_UNEXPECTED'}
  $phase='SCHEMA'
  # sqlite3 dot-command parser treats backslash as an escape even in quoted paths.
  # This tree has a fixed, space-free path; Windows SQLite accepts forward slashes.
  $command='.read '+$schema.Replace('\','/')
  $null=Sql $exe $db $command
  if(-not [IO.File]::Exists($db)){Fail 'DB_NOT_CREATED'}
  $quick=Sql $exe $db 'PRAGMA quick_check;'
  if($quick -ne 'ok'){Fail 'DB_QUICK_CHECK_FAILED'}
  $tables=Sql $exe $db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('customers','change_inbox','ingestion_checkpoint','scan_runs');"
  if($tables -ne '4'){Fail 'SCHEMA_TABLES_NOT_FOUR'}
  $before=Sql $exe $db 'SELECT count(*) FROM customers;'
  if($before -ne '0'){Fail 'DB_NOT_EMPTY'}
  $phase='TRANSACTION'
  $q="BEGIN;INSERT INTO customers(onec_guid,onec_type,buyer,deletion_mark,invalid,updated_at_utc,needs_review) VALUES ('00000000-0000-0000-0000-000000000001','PERSON',1,0,0,'2026-10-15T00:00:00Z',0);SELECT count(*) FROM customers;ROLLBACK;"
  $during=Sql $exe $db $q
  if($during -ne '1'){Fail 'SYNTHETIC_INSERT_FAILED'}
  $after=Sql $exe $db 'SELECT count(*) FROM customers;'
  if($after -ne '0'){Fail 'ROLLBACK_FAILED'}
  $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  $line='UTC='+$stamp+';STATUS=EMPTY_DB_PASS;IDENTITY=LOCAL_SERVICE;CUSTOMERS=0;ONEC_CALLS=0;BITRIX_CALLS=0'
  [IO.File]::WriteAllText($statePath,$line,[Text.Encoding]::ASCII)
  'RUN_AS_LOCAL_SERVICE=YES'
  'SQLITE_VERSION=3.43.2'
  'DB_QUICK_CHECK=ok'
  'SCHEMA_TABLES=4'
  'SYNTHETIC_TRANSACTION_ROLLBACK=PASS'
  'CUSTOMERS_COUNT=0'
  'STATUS_PERSISTED=YES'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_EMPTY_SMOKE'
}catch{
  $gate='RUNTIME_ERROR'
  $message=$_.Exception.Message
  if($message -match '^CUSTOMER_STORE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  if($null -ne $statePath -and [IO.Directory]::Exists((Split-Path $statePath -Parent))){
    try{[IO.File]::WriteAllText($statePath,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
  }
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_EMPTY_SMOKE;GATE='+$gate+';PHASE='+$phase
  exit 1
}

#requires -version 2
# Local-only SQLite compatibility + empty schema smoke. NO customer records.
# Does NOT modify the live MspBitrix24Bridge task, config, data or 1C.
param([string]$ExpectedComputerName='SRV',[string]$ExpectedSchemaSha256)
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Reason){throw ('STORE_'+$Reason)}
function Sha256([string]$File){
  $h=New-Object System.Security.Cryptography.SHA256Managed
  try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($File))).Replace('-','').ToLowerInvariant())}finally{$h.Clear()}
}
function Download([string]$Url,[string]$Out,[string]$Curl,[string]$Ca){
  & $Curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $Ca --proto '=https' --max-redirs 0 --output $Out $Url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($Out)){Fail 'DOWNLOAD_FAILED'}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  if($ExpectedSchemaSha256 -notmatch '^[0-9a-fA-F]{64}$'){Fail 'SCHEMA_HASH_REQUIRED'}
  $bridge='C:\ProgramData\MspBitrix24Bridge'
  $config=Join-Path $bridge 'config\bridge.ini'
  if(-not [IO.File]::Exists($config)){Fail 'BRIDGE_CONFIG_MISSING'}
  $policy=[IO.File]::ReadAllText($config)
  foreach($gate in @('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')){
    if($policy -notmatch ('(?m)^'+[regex]::Escape($gate)+'\s*$')){Fail 'BRIDGE_NOT_SAFE_IDLE'}
  }
  $curlBase='C:\Users\parshin\Desktop\OnecHttpsPortable_20261013_095710'
  $curl=Join-Path $curlBase 'curl.exe'
  $ca=Join-Path $curlBase 'curl-ca-bundle.crt'
  if(-not [IO.File]::Exists($curl) -or -not [IO.File]::Exists($ca)){Fail 'PORTABLE_TLS_NOT_FOUND'}
  $dir=Join-Path $env:LOCALAPPDATA 'MspCustomerStorePilot'
  if([IO.Directory]::Exists($dir)){Fail 'PILOT_DIRECTORY_ALREADY_EXISTS'}
  if([IO.File]::Exists($dir)){Fail 'PILOT_PATH_IS_FILE'}
  if([string]::IsNullOrEmpty($env:LOCALAPPDATA)){Fail 'LOCALAPPDATA_MISSING'}
  [void][IO.Directory]::CreateDirectory($dir)
  'PILOT_DIRECTORY_CREATED=YES'
  $zip=Join-Path $dir 'sqlite-tools-win32-x86-3430200.zip'
  $sqlite=Join-Path $dir 'sqlite3.exe'
  $db=Join-Path $dir 'customers.db'
  $schema=Join-Path $dir 'customer-store.sql'
  $phase='OFFICIAL_SQLITE_DOWNLOAD'
  Download 'https://www.sqlite.org/2023/sqlite-tools-win32-x86-3430200.zip' $zip $curl $ca
  $expectedZip='fae9efccf4469ca69be5d418fc088593cdb86e07a1b211bdb85463591a923b02'
  if((Sha256 $zip) -ne $expectedZip){Fail 'OFFICIAL_ZIP_SHA256_MISMATCH'}
  'OFFICIAL_ZIP_SHA256=PASS'
  $phase='EXTRACT_SQLITE'
  $shell=New-Object -ComObject Shell.Application
  $zipFolder=$shell.NameSpace([string]$zip)
  $destination=$shell.NameSpace([string]$dir)
  if($null -eq $zipFolder -or $null -eq $destination){Fail 'ZIP_SHELL_UNAVAILABLE'}
  $entry=$zipFolder.ParseName('sqlite3.exe')
  if($null -eq $entry -or $entry.IsFolder){Fail 'EXPECTED_EXE_NOT_IN_ZIP'}
  $destination.CopyHere($entry,0x14)
  $found=$false
  for($i=0;$i -lt 60;$i++){
    Start-Sleep -Milliseconds 500
    if([IO.File]::Exists($sqlite)){
      try{
        $bytes=[IO.File]::ReadAllBytes($sqlite)
        if($bytes.Length -ge 250000 -and $bytes[0] -eq 77 -and $bytes[1] -eq 90){$found=$true;break}
      }catch{}
    }
  }
  if(-not $found){Fail 'EXTRACTED_SQLITE_NOT_READY'}
  $phase='SQLITE_EXECUTION'
  $version=& $sqlite -version 2>$null
  if($LASTEXITCODE -ne 0 -or (-join $version) -notmatch '^3\.43\.2\s'){Fail 'SQLITE_VERSION_OR_RUNTIME_FAILED'}
  'SQLITE_VERSION=3.43.2'
  'SQLITE_32BIT_TOOL_ON_X64=YES'
  'SQLITE_EXE_SHA256='+(Sha256 $sqlite)
  $phase='SCHEMA_DOWNLOAD'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/45b21a4d4090fbccaf8cb802274a61a4018286cf/integrations/msp-bitrix24-bridge/schema/customer-store.sql'
  Download $url $schema $curl $ca
  if((Sha256 $schema) -ne $ExpectedSchemaSha256.ToLowerInvariant()){Fail 'SCHEMA_SHA256_MISMATCH'}
  'SCHEMA_SHA256=PASS'
  $phase='EMPTY_DATABASE_CREATE'
  $apply=& $sqlite -batch -bail $db ('.read "'+$schema+'"') 2>&1
  if($LASTEXITCODE -ne 0){Fail 'SCHEMA_APPLY_FAILED'}
  if(-not [IO.File]::Exists($db)){Fail 'DB_NOT_CREATED'}
  $check=& $sqlite -batch -bail $db 'PRAGMA quick_check;' 2>&1
  if($LASTEXITCODE -ne 0 -or (-join $check).Trim() -ne 'ok'){Fail 'QUICK_CHECK_FAILED'}
  $tables=& $sqlite -batch -bail $db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('customers','change_inbox','ingestion_checkpoint','scan_runs');" 2>&1
  if($LASTEXITCODE -ne 0 -or (-join $tables).Trim() -ne '4'){Fail 'EXPECTED_TABLES_MISSING'}
  $phase='SYNTHETIC_TRANSACTION_TEST'
  $sql="BEGIN;INSERT INTO customers(onec_guid,onec_type,buyer,deletion_mark,invalid,updated_at_utc,needs_review) VALUES ('00000000-0000-0000-0000-000000000001','PERSON',1,0,0,'2026-10-15T00:00:00Z',0);SELECT count(*) FROM customers;ROLLBACK;"
  $r=& $sqlite -batch -bail $db $sql 2>&1
  if($LASTEXITCODE -ne 0 -or (-join $r).Trim() -ne '1'){Fail 'TRANSACTION_TEST_FAILED'}
  $empty=& $sqlite -batch -bail $db 'SELECT count(*) FROM customers;' 2>&1
  if($LASTEXITCODE -ne 0 -or (-join $empty).Trim() -ne '0'){Fail 'ROLLBACK_OR_EMPTY_CHECK_FAILED'}
  'DB_QUICK_CHECK=ok'
  'EXPECTED_TABLES=4'
  'SYNTHETIC_TRANSACTION_ROLLBACK=PASS'
  'CUSTOMERS_COUNT=0'
  'PILOT_DB_PATH='+$db
  'LIVE_BRIDGE_DATA_MODIFIED=NO'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'SYSTEM_TASK_CHANGED=NO'
  'RESULT=PASS;STAGE=SRV_SQLITE_EMPTY_PILOT'
}catch{
  $gate='RUNTIME_ERROR'
  $msg=$_.Exception.Message
  if($msg -match '^STORE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_SQLITE_EMPTY_PILOT;GATE='+$gate
  'FAILURE_PHASE='+$phase
  'LIVE_BRIDGE_DATA_MODIFIED=NO'
  'NO_AUTOMATIC_RETRY=YES'
}

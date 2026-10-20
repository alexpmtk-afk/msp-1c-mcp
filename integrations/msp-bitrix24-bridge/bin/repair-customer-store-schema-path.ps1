#requires -version 2
# One-time verified recovery of failed SCHEMA smoke on physical SRV.
# Only swaps the existing machine-owned smoke script and runs its existing
# LOCAL SERVICE task manually. No 1C, Bitrix, task, trigger or ACL edits.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Why){throw ('FIX_'+$Why)}
function Sha([string]$File){
  $h=New-Object Security.Cryptography.SHA256Managed
  try{
    $digest=$h.ComputeHash([IO.File]::ReadAllBytes($File))
    return ([BitConverter]::ToString($digest)).Replace('-','').ToLowerInvariant()
  }finally{$h.Clear()}
}
function Check([string]$File,[string]$Expected){
  if(-not [IO.File]::Exists($File)){Fail 'REQUIRED_FILE_NOT_FOUND'}
  if(([IO.File]::GetAttributes($File) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  if((Sha $File) -ne $Expected){Fail 'PINNED_FILE_SHA256_MISMATCH'}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'NATIVE_PS2_X64_REQUIRED'}
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
  if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $other='C:\ProgramData\MspBitrix24Bridge'
  $flags=[IO.File]::ReadAllText((Join-Path $other 'config\bridge.ini'),[Text.Encoding]::ASCII)
  foreach($f in @('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')){
    if($flags -notmatch ('(?m)^'+[regex]::Escape($f)+'\s*$')){Fail 'OTHER_BRIDGE_NOT_SAFE_IDLE'}
  }
  $bin=Join-Path $root 'bin'
  $cfg=Join-Path $root 'config'
  $data=Join-Path $root 'data'
  $state=Join-Path $root 'state'
  $stage=Join-Path $root 'staging'
  foreach($dir in @($root,$bin,$cfg,$data,$state,$stage,(Join-Path $root 'schema'))){
    if(-not [IO.Directory]::Exists($dir)){Fail 'MACHINE_DIR_MISSING'}
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'MACHINE_DIR_REPARSE'}
  }
  $db=Join-Path $data 'customers.db'
  if([IO.File]::Exists($db)){Fail 'DB_EXISTS_REVIEW_BEFORE_REPAIR'}
  $active=Join-Path $bin 'smoke-customer-store-service.ps1'
  $newSha='56f6d629241380828563cdf8551fefb1b53fbb71aeb06cfa4e2ab4a71ad3131d'
  $oldSha='b2753f937e1e2c941440b69cbb2596655909f7a11892c61d34e44aa95c49b388'
  $schema=Join-Path $root 'schema\customer-store.sql'
  $sqlite=Join-Path $bin 'sqlite3.exe'
  $collectorCfg=Join-Path $cfg 'collector.ini'
  $curl=Join-Path $bin 'curl.exe'
  $ca=Join-Path $cfg 'curl-ca-bundle.crt'
  Check $active $oldSha
  Check $schema '50748aada5273f60a8056cb1358334cf3fe3c221b67ca8766c8d18a9003b30a3'
  Check $collectorCfg '38d5d83c423f560c5e087edd1a28249eb84197282725fec2a28df2da20bad695'
  foreach($f in @($sqlite,$curl,$ca)){if(-not [IO.File]::Exists($f)){Fail 'MACHINE_RUNTIME_MISSING'}}
  $collector=[IO.File]::ReadAllText($collectorCfg,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($collector -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'COLLECTOR_NOT_SAFE_IDLE'}
  }
  $stateFile=Join-Path $state 'status.txt'
  if(-not [IO.File]::Exists($stateFile)){Fail 'SMOKE_FAILURE_STATUS_MISSING'}
  $stateText=[IO.File]::ReadAllText($stateFile,[Text.Encoding]::ASCII).Trim()
  if($stateText -ne 'STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=SCHEMA'){Fail 'UNEXPECTED_SERVICE_STATUS'}
  $sched=New-Object -ComObject Schedule.Service
  $sched.Connect()
  $task=$sched.GetFolder('\').GetTask('MspCustomerStoreSync')
  if($null -eq $task){Fail 'COLLECTOR_TASK_MISSING'}
  $who=$task.Definition.Principal.UserId
  if($who -eq 'S-1-5-19'){$sid=$who}else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $who).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($sid -ne 'S-1-5-19'){Fail 'TASK_NOT_LOCAL_SERVICE'}
  if(-not $task.Enabled -or $task.State -eq 4){Fail 'TASK_DISABLED_OR_RUNNING'}
  if($task.Definition.Triggers.Count -ne 1){Fail 'TASK_TRIGGER_COUNT_UNEXPECTED'}
  foreach($trigger in $task.Definition.Triggers){
    if($trigger.Enabled){Fail 'TASK_AUTOSTART_ALREADY_ENABLED'}
  }
  if($task.Definition.Actions.Count -ne 1){Fail 'TASK_ACTION_COUNT_UNEXPECTED'}
  $action=$task.Definition.Actions.Item(1)
  if($action.Arguments -notlike ('*'+$active+'*')){Fail 'TASK_ACTION_SCRIPT_MISMATCH'}
  if(($action.Path+' '+$action.Arguments) -match '(?i)[A-Z]:\\Users\\'){Fail 'TASK_USER_PROFILE_DEPENDENCY'}
  $candidate=Join-Path $stage 'smoke-schema-path-fixed.ps1.new'
  $backup=Join-Path $stage 'smoke-before-schema-path-fix.ps1.bak'
  if([IO.File]::Exists($candidate) -or [IO.File]::Exists($backup)){Fail 'REPAIR_FILE_ALREADY_EXISTS'}
  $phase='MEMORY_SQLITE_PREFLIGHT'
  $version=@(& $sqlite -version 2>&1)
  if($LASTEXITCODE -ne 0 -or (($version -join ' ') -notmatch '^3\.43\.2(\s|$)')){Fail 'SQLITE_VERSION_UNEXPECTED'}
  $readCmd='.read '+$schema.Replace('\','/')
  $output=@(& $sqlite -batch -bail ':memory:' $readCmd 2>&1)
  if($LASTEXITCODE -ne 0){Fail 'FORWARD_SLASH_MEMORY_TEST_FAILED'}
  'SQLITE_MEMORY_SCHEMA_PATH=PASS'
  $phase='FETCH_PINNED_PATCH'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/cfca93d11b3600300b3b7ba7651d12abe3e2ce15/integrations/msp-bitrix24-bridge/bin/smoke-customer-store-service.ps1'
  & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $candidate $url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($candidate)){Fail 'PINNED_PATCH_DOWNLOAD_FAILED'}
  Check $candidate $newSha
  'PATCH_SHA256=PASS'
  $errors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($candidate,[Text.Encoding]::ASCII),[ref]$errors)
  if($errors -and $errors.Count -gt 0){Fail 'PS2_PATCH_SYNTAX_FAILED'}
  $phase='ATOMIC_REPLACE'
  [IO.File]::Replace($candidate,$active,$backup)
  Check $active $newSha
  Check $backup $oldSha
  'SCRIPT_REPLACED_ATOMICALLY=YES'
  'OLD_SCRIPT_BACKUP_SHA256=PASS'
  $phase='LOCAL_SERVICE_RETEST'
  $started=[DateTime]::UtcNow
  $null=$task.Run($null)
  $pass=$false
  for($i=0;$i -lt 100;$i++){
    Start-Sleep -Milliseconds 500
    if(-not [IO.File]::Exists($stateFile)){continue}
    $info=New-Object IO.FileInfo -ArgumentList $stateFile
    if($info.LastWriteTimeUtc -lt $started.AddSeconds(-2)){continue}
    $line=[IO.File]::ReadAllText($stateFile,[Text.Encoding]::ASCII).Trim()
    if($line -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
      'SERVICE_FAILURE_GATE='+$Matches[1]
      'SERVICE_FAILURE_PHASE='+$Matches[2]
      Fail 'LOCAL_SERVICE_RETEST_FAILED'
    }
    if($line -match '^UTC=([^;]+);STATUS=EMPTY_DB_PASS;IDENTITY=LOCAL_SERVICE;CUSTOMERS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){
      $time=[DateTime]::Parse($Matches[1]).ToUniversalTime()
      if($time -ge $started.AddSeconds(-2)){$pass=$true;break}
    }
  }
  if(-not $pass){Fail 'LOCAL_SERVICE_STATUS_NOT_CONFIRMED'}
  if(-not [IO.File]::Exists($db)){Fail 'DB_NOT_CREATED'}
  $quick=@(& $sqlite -batch -bail $db 'PRAGMA quick_check;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($quick -join '').Trim() -ne 'ok'){Fail 'DB_QUICK_CHECK_FAILED'}
  $tables=@(& $sqlite -batch -bail $db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('customers','change_inbox','ingestion_checkpoint','scan_runs');" 2>&1)
  if($LASTEXITCODE -ne 0 -or ($tables -join '').Trim() -ne '4'){Fail 'SCHEMA_TABLE_COUNT_MISMATCH'}
  $count=@(& $sqlite -batch -bail $db 'SELECT count(*) FROM customers;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($count -join '').Trim() -ne '0'){Fail 'CUSTOMERS_NONEMPTY'}
  'LOCAL_SERVICE_EMPTY_DB_SMOKE=PASS'
  'DB_QUICK_CHECK=ok'
  'SCHEMA_TABLES=4'
  'CUSTOMERS_COUNT=0'
  'COLLECTOR_TASK_RUN_AS_LOCAL_SERVICE=YES'
  'COLLECTOR_BOOT_AUTOSTART=OFF'
  'TASK_DEFINITION_CHANGED=NO'
  'OTHER_BRIDGE_CHANGED=NO'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_SCHEMA_PATH_REPAIR'
}catch{
  $reason='RUNTIME_ERROR'
  if($_.Exception.Message -match '^FIX_([A-Z0-9_]+)$'){$reason=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_SCHEMA_PATH_REPAIR;GATE='+$reason
  'FAILURE_PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

#requires -version 2
# Offline continuation from already-installed SQLite and staged raw GitHub SQL.
# On SRV only, single machine-owned LOCAL SERVICE task, no API requests.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Why){throw ('RESUME_'+$Why)}
function Hash([string]$File){
  $s=New-Object Security.Cryptography.SHA256Managed
  try{$d=$s.ComputeHash([IO.File]::ReadAllBytes($File));return ([BitConverter]::ToString($d)).Replace('-','').ToLowerInvariant()}finally{$s.Clear()}
}
function OnlyNames([string]$Dir,[string[]]$Allowed){
  if(-not [IO.Directory]::Exists($Dir)){Fail 'DIRECTORY_MISSING'}
  if(([IO.File]::GetAttributes($Dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DIRECTORY'}
  foreach($entry in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction Stop)){
    if($Allowed -notcontains $entry.Name){Fail 'UNEXPECTED_ITEM'}
    if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_ITEM'}
  }
}
function CheckFile([string]$File,[string]$Expected){
  if(-not [IO.File]::Exists($File)){Fail 'EXPECTED_FILE_MISSING'}
  if(([IO.File]::GetAttributes($File) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  if((Hash $File) -ne $Expected){Fail 'FILE_SHA256_MISMATCH'}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'NATIVE_PS2_X64_REQUIRED'}
  $win=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $win
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $old='C:\ProgramData\MspBitrix24Bridge'
  $safe=[IO.File]::ReadAllText((Join-Path $old 'config\bridge.ini'),[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')){
    if($safe -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'OLD_BRIDGE_NOT_SAFE_IDLE'}
  }
  $sched=New-Object -ComObject Schedule.Service
  $sched.Connect()
  $folder=$sched.GetFolder('\')
  $existing=$null
  try{$existing=$folder.GetTask('MspCustomerStoreSync')}catch{}
  if($null -ne $existing){Fail 'TASK_ALREADY_EXISTS'}
  $subdirs=@('bin','config','schema','data','state','logs','staging','secrets','backups')
  OnlyNames $root $subdirs
  $bin=Join-Path $root 'bin'
  $cfg=Join-Path $root 'config'
  $schemaDir=Join-Path $root 'schema'
  $staging=Join-Path $root 'staging'
  OnlyNames $bin @('curl.exe','sqlite3.exe','smoke-customer-store-service.ps1')
  OnlyNames $cfg @('curl-ca-bundle.crt','collector.ini')
  OnlyNames $schemaDir @()
  OnlyNames $staging @('sqlite-tools-win32-x86-3430200.zip','smoke-customer-store-service.ps1.verified','collector.ini.verified','customer-store.sql.verified')
  foreach($n in @('data','state','logs','secrets','backups')){OnlyNames (Join-Path $root $n) @()}
  $exe=Join-Path $bin 'sqlite3.exe'
  $smoke=Join-Path $bin 'smoke-customer-store-service.ps1'
  $conf=Join-Path $cfg 'collector.ini'
  $stageSmoke=Join-Path $staging 'smoke-customer-store-service.ps1.verified'
  $stageConf=Join-Path $staging 'collector.ini.verified'
  $stageSql=Join-Path $staging 'customer-store.sql.verified'
  $zip=Join-Path $staging 'sqlite-tools-win32-x86-3430200.zip'
  $smokeSha='b2753f937e1e2c941440b69cbb2596655909f7a11892c61d34e44aa95c49b388'
  $confSha='38d5d83c423f560c5e087edd1a28249eb84197282725fec2a28df2da20bad695'
  $sqlSha='50748aada5273f60a8056cb1358334cf3fe3c221b67ca8766c8d18a9003b30a3'
  CheckFile $zip 'fae9efccf4469ca69be5d418fc088593cdb86e07a1b211bdb85463591a923b02'
  CheckFile $stageSmoke $smokeSha
  CheckFile $stageConf $confSha
  CheckFile $stageSql $sqlSha
  CheckFile $smoke $smokeSha
  CheckFile $conf $confSha
  $flags=[IO.File]::ReadAllText($conf,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($flags -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'UNSAFE_COLLECTOR_FLAGS'}
  }
  foreach($f in @((Join-Path $bin 'curl.exe'),(Join-Path $cfg 'curl-ca-bundle.crt'))){
    if(-not [IO.File]::Exists($f)){Fail 'MACHINE_TLS_MISSING'}
  }
  $v=@(& $exe -version 2>&1)
  if($LASTEXITCODE -ne 0 -or (($v -join ' ') -notmatch '^3\.43\.2(\s|$)')){Fail 'SQLITE_RUNTIME_UNEXPECTED'}
  foreach($n in @('data','state')){
    $acl=[IO.Directory]::GetAccessControl((Join-Path $root $n))
    $allowed=$false
    foreach($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
      if($ace.IdentityReference.Value -eq 'S-1-5-19' -and $ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and (($ace.FileSystemRights -band [Security.AccessControl.FileSystemRights]::WriteData) -ne 0)){$allowed=$true}
    }
    if(-not $allowed){Fail 'LOCAL_SERVICE_WRITABLE_ACL_MISSING'}
  }
  'PINNED_STAGED_SQL_SHA256=PASS'
  'PINNED_OTHER_FILES_SHA256=PASS'
  'SYSTEM_SQLITE_VERSION=3.43.2'
  $phase='COPY_PINNED_SQL'
  $destination=Join-Path $schemaDir 'customer-store.sql'
  if([IO.File]::Exists($destination)){Fail 'SQL_TARGET_COLLISION'}
  [IO.File]::Copy($stageSql,$destination,$false)
  CheckFile $destination $sqlSha
  'SCHEMA_COPY_SHA256=PASS'
  $phase='CREATE_SERVICE_TASK'
  $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  if(-not $account){Fail 'LOCAL_SERVICE_UNRESOLVED'}
  $def=$sched.NewTask(0)
  $def.RegistrationInfo.Description='Standalone SRV customer SQLite safe empty-store smoke'
  $def.Principal.UserId=$account
  $def.Principal.LogonType=5
  $def.Principal.RunLevel=0
  $def.Settings.Enabled=$true
  $def.Settings.StartWhenAvailable=$true
  $def.Settings.ExecutionTimeLimit='PT2M'
  $def.Settings.MultipleInstances=2
  $boot=$def.Triggers.Create(8)
  $boot.Enabled=$false
  $act=$def.Actions.Create(0)
  $act.Path=Join-Path $PSHOME 'powershell.exe'
  $act.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $bin 'smoke-customer-store-service.ps1')+'" -ExpectedComputerName SRV'
  $null=$folder.RegisterTaskDefinition('MspCustomerStoreSync',$def,2,$account,$null,5,$null)
  $task=$folder.GetTask('MspCustomerStoreSync')
  if(-not $task.Enabled -or $task.Definition.Triggers.Count -ne 1 -or $task.Definition.Triggers.Item(1).Enabled){Fail 'TASK_TRIGGER_NOT_DISABLED'}
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList @($task.Definition.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
  if($sid -ne 'S-1-5-19'){Fail 'TASK_IDENTITY_MISMATCH'}
  $phase='RUN_SERVICE_EMPTY_SMOKE'
  $start=[DateTime]::UtcNow
  $null=$task.Run($null)
  $status=Join-Path $root 'state\status.txt'
  $passed=$false
  for($i=0;$i -lt 100;$i++){
    Start-Sleep -Milliseconds 500
    if(-not [IO.File]::Exists($status)){continue}
    $s=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII).Trim()
    if($s -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
      'SERVICE_SMOKE_FAILURE_GATE='+$Matches[1]
      'SERVICE_SMOKE_FAILURE_PHASE='+$Matches[2]
      Fail 'SERVICE_SMOKE_REPORTED_FAIL'
    }
    if($s -match '^UTC=([^;]+);STATUS=EMPTY_DB_PASS;IDENTITY=LOCAL_SERVICE;CUSTOMERS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){
      $stamp=[DateTime]::Parse($Matches[1]).ToUniversalTime()
      if($stamp -ge $start.AddSeconds(-2)){$passed=$true;break}
    }
  }
  if(-not $passed){Fail 'SERVICE_SMOKE_NOT_CONFIRMED'}
  $db=Join-Path $root 'data\customers.db'
  if(-not [IO.File]::Exists($db)){Fail 'DB_MISSING_AFTER_SERVICE_SMOKE'}
  $rows=@(& $exe -batch -bail $db 'SELECT count(*) FROM customers;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($rows -join '').Trim() -ne '0'){Fail 'DB_NONEMPTY_OR_UNREADABLE'}
  $quick=@(& $exe -batch -bail $db 'PRAGMA quick_check;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($quick -join '').Trim() -ne 'ok'){Fail 'DB_INTEGRITY_FAIL'}
  'STORE_PATH='+$root
  'SERVICE_IDENTITY=LOCAL_SERVICE'
  'SERVICE_EMPTY_SMOKE=PASS'
  'DB_QUICK_CHECK=ok'
  'CUSTOMERS_COUNT=0'
  'COLLECTOR_TASK_EXISTS=YES'
  'COLLECTOR_BOOT_TRIGGER_ENABLED=NO'
  'RUNTIME_DEPENDENCY_USER_PROFILE=NO'
  'EXISTING_BRIDGE_CHANGED=NO'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_SCHEMA_RESUME'
}catch{
  $reason='RUNTIME_ERROR'
  $m=$_.Exception.Message
  if($m -match '^RESUME_([A-Z0-9_]+)$'){$reason=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_SCHEMA_RESUME;GATE='+$reason
  'FAILURE_PHASE='+$phase
  'EXCEPTION_TYPE='+$_.Exception.GetType().Name
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

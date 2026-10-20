#requires -version 2
# Resume ONLY the proven curl+CA partial install of MspCustomerStore on SRV.
# No 1C or Bitrix calls. No change to other tasks. Boot trigger stays off.
param([string]$ExpectedComputerName='SRV',[string]$BootstrapTlsDir)
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Why){throw ('RESUME_'+$Why)}
function Hash([string]$File){
  $s=New-Object Security.Cryptography.SHA256Managed
  try{
    $hash=$s.ComputeHash([IO.File]::ReadAllBytes($File))
    return ([BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant()
  }finally{$s.Clear()}
}
function Fetch([string]$Url,[string]$Destination,[string]$Curl,[string]$CA){
  if([IO.File]::Exists($Destination)){Fail 'STAGING_FILE_COLLISION'}
  & $Curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $CA --proto '=https' --max-redirs 0 --output $Destination $Url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($Destination)){Fail 'HTTPS_DOWNLOAD_FAILED'}
}
function OnlyNames([string]$Dir,[string[]]$Allowed){
  foreach($item in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction Stop)){
    if($Allowed -notcontains $item.Name){Fail 'UNEXPECTED_FILE_OR_DIRECTORY'}
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_ITEM'}
  }
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'NATIVE_PS2_X64_REQUIRED'}
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $id
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $legacy='C:\ProgramData\MspBitrix24Bridge'
  $policyFile=Join-Path $legacy 'config\bridge.ini'
  if(-not [IO.File]::Exists($policyFile)){Fail 'BRIDGE_POLICY_MISSING'}
  $policy=[IO.File]::ReadAllText($policyFile,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')){
    if($policy -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'LEGACY_BRIDGE_NOT_SAFE_IDLE'}
  }
  $sched=New-Object -ComObject Schedule.Service
  $sched.Connect()
  $folder=$sched.GetFolder('\')
  $existing=$null
  try{$existing=$folder.GetTask('MspCustomerStoreSync')}catch{}
  if($null -ne $existing){Fail 'COLLECTOR_TASK_ALREADY_EXISTS'}
  $dirNames=@('bin','config','schema','data','state','logs','staging','secrets','backups')
  if(-not [IO.Directory]::Exists($root)){Fail 'PARTIAL_ROOT_MISSING'}
  if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'ROOT_REPARSE'}
  foreach($n in $dirNames){
    $p=Join-Path $root $n
    if(-not [IO.Directory]::Exists($p)){Fail 'PARTIAL_DIRECTORY_MISSING'}
    if(([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'DIRECTORY_REPARSE'}
  }
  OnlyNames $root $dirNames
  $bin=Join-Path $root 'bin'
  $cfg=Join-Path $root 'config'
  $staging=Join-Path $root 'staging'
  OnlyNames $bin @('curl.exe')
  OnlyNames $cfg @('curl-ca-bundle.crt')
  foreach($n in @('schema','data','state','logs','staging','secrets','backups')){
    OnlyNames (Join-Path $root $n) @()
  }
  if([string]::IsNullOrEmpty($BootstrapTlsDir) -or -not [IO.Directory]::Exists($BootstrapTlsDir)){Fail 'BOOTSTRAP_PATH_MISSING'}
  $sourceCurl=Join-Path $BootstrapTlsDir 'curl.exe'
  $sourceCA=Join-Path $BootstrapTlsDir 'curl-ca-bundle.crt'
  $curl=Join-Path $bin 'curl.exe'
  $ca=Join-Path $cfg 'curl-ca-bundle.crt'
  foreach($f in @($sourceCurl,$sourceCA,$curl,$ca)){
    if(-not [IO.File]::Exists($f)){Fail 'PARTIAL_TLS_FILE_MISSING'}
    if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'TLS_REPARSE_FILE'}
  }
  if((Hash $sourceCurl) -ne (Hash $curl) -or (Hash $sourceCA) -ne (Hash $ca)){Fail 'BOOTSTRAP_TLS_HASH_MISMATCH'}
  if(@(Get-ChildItem -LiteralPath $BootstrapTlsDir -Filter '*.dll' -ErrorAction Stop).Count -ne 0){Fail 'UNVERIFIED_TLS_DLL_DEPENDENCIES'}
  $phase='SYSTEM_CURL_VERIFY'
  $curlVersion=@(& $curl --version 2>&1)
  if($LASTEXITCODE -ne 0 -or (($curlVersion -join ' ') -notmatch '^curl\s+\d')){Fail 'SYSTEM_CURL_FAILED'}
  'CURL_SYSTEM_VERSION=PASS'
  'CURL_SYSTEM_HASH=PASS'
  $phase='SQLITE_DOWNLOAD'
  $zip=Join-Path $staging 'sqlite-tools-win32-x86-3430200.zip'
  Fetch 'https://www.sqlite.org/2023/sqlite-tools-win32-x86-3430200.zip' $zip $curl $ca
  if((Hash $zip) -ne 'fae9efccf4469ca69be5d418fc088593cdb86e07a1b211bdb85463591a923b02'){Fail 'SQLITE_ZIP_SHA256_MISMATCH'}
  'SQLITE_ARCHIVE_SHA256=PASS'
  $phase='SQLITE_EXTRACT'
  $shell=New-Object -ComObject Shell.Application
  $archive=$shell.NameSpace([string]$zip)
  $dest=$shell.NameSpace([string]$bin)
  if($null -eq $archive -or $null -eq $dest){Fail 'ZIP_COM_UNAVAILABLE'}
  $entry=$archive.ParseName('sqlite3.exe')
  if($null -eq $entry -or $entry.IsFolder){Fail 'SQLITE_ENTRY_MISSING'}
  $exe=Join-Path $bin 'sqlite3.exe'
  if([IO.File]::Exists($exe)){Fail 'SQLITE_EXE_COLLISION'}
  $dest.CopyHere($entry,0x14)
  $stable=0
  $previous=-1
  for($i=0;$i -lt 100;$i++){
    Start-Sleep -Milliseconds 300
    if([IO.File]::Exists($exe)){
      try{
        $length=([IO.FileInfo]$exe).Length
        if($length -ge 250000 -and $length -eq $previous){$stable++}else{$stable=0}
        $previous=$length
        if($stable -ge 4){break}
      }catch{}
    }
  }
  if($stable -lt 4){Fail 'SQLITE_EXTRACT_TIMEOUT'}
  $sqliteVersion=@(& $exe -version 2>&1)
  if($LASTEXITCODE -ne 0 -or (($sqliteVersion -join ' ') -notmatch '^3\.43\.2(\s|$)')){Fail 'SQLITE_EXE_INCOMPATIBLE'}
  'SQLITE_VERSION=3.43.2'
  $phase='DOWNLOAD_PINNED_SCHEMAS'
  $prefix='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/a4f583ac7404cbad2601457ceb2f79c86ec807f1/integrations/msp-bitrix24-bridge/'
  $manifest=@(
    @('bin/smoke-customer-store-service.ps1','bin\smoke-customer-store-service.ps1','b2753f937e1e2c941440b69cbb2596655909f7a11892c61d34e44aa95c49b388'),
    @('config/collector.ini','config\collector.ini','38d5d83c423f560c5e087edd1a28249eb84197282725fec2a28df2da20bad695'),
    @('schema/customer-store.sql','schema\customer-store.sql','50748aada5273f60a8056cb1358334cf3fe3c221b67ca8766c8d18a9003b30a3')
  )
  foreach($row in $manifest){
    $staged=Join-Path $staging ((Split-Path $row[0] -Leaf)+'.verified')
    Fetch ($prefix+$row[0]) $staged $curl $ca
    if((Hash $staged) -ne $row[2]){Fail 'SOURCE_SHA256_MISMATCH'}
    $final=Join-Path $root $row[1]
    if([IO.File]::Exists($final)){Fail 'SOURCE_TARGET_COLLISION'}
    [IO.File]::Copy($staged,$final,$false)
    if((Hash $final) -ne $row[2]){Fail 'STAGED_COPY_HASH_MISMATCH'}
  }
  'PINNED_SOURCES_SHA256=PASS'
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
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_PARTIAL_INSTALL_RESUMED'
}catch{
  $reason='RUNTIME_ERROR'
  $m=$_.Exception.Message
  if($m -match '^RESUME_([A-Z0-9_]+)$'){$reason=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_PARTIAL_INSTALL_RESUMED;GATE='+$reason
  'FAILURE_PHASE='+$phase
  'EXCEPTION_TYPE='+$_.Exception.GetType().Name
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

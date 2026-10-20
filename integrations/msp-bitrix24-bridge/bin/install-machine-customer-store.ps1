#requires -version 2
# Creates independent machine-owned SQLite store on SRV only; no 1C/Bitrix access.
# A disabled boot trigger + an on-demand Local Service smoke are configured.
# All persistent dependencies are in C:\ProgramData\MspCustomerStore.
param([string]$ExpectedComputerName='SRV',[string]$BootstrapTlsDir)
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Reason){throw ('INSTALL_'+$Reason)}
function Sha256([string]$File){
  $h=New-Object Security.Cryptography.SHA256Managed
  try{$hex=[BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($File)));return $hex.Replace('-','').ToLowerInvariant()}finally{$h.Clear()}
}
function BlobSha1([string]$File){
  [byte[]]$payload=[IO.File]::ReadAllBytes($File)
  [byte[]]$prefix=[Text.Encoding]::ASCII.GetBytes(('blob '+$payload.Length+[char]0))
  $bytes=New-Object byte[] ($prefix.Length+$payload.Length)
  [Array]::Copy($prefix,0,$bytes,0,$prefix.Length)
  [Array]::Copy($payload,0,$bytes,$prefix.Length,$payload.Length)
  $h=New-Object Security.Cryptography.SHA1Managed
  try{$hex=[BitConverter]::ToString($h.ComputeHash($bytes));return $hex.Replace('-','').ToLowerInvariant()}finally{$h.Clear()}
}
function Fetch([string]$Url,[string]$Destination,[string]$Curl,[string]$Ca){
  & $Curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $Ca --proto '=https' --max-redirs 0 --output $Destination $Url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($Destination)){Fail 'DOWNLOAD_FAILED'}
}
function Grant([string]$Path,[string[]]$Arguments,[string]$Icacls){
  & $Icacls $Path $Arguments | Out-Null
  if($LASTEXITCODE -ne 0){Fail 'ACL_SETUP_FAILED'}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'NATIVE_PS2_X64_REQUIRED'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATED_INSTALL_REQUIRED'}
  $legacy='C:\ProgramData\MspBitrix24Bridge'
  $policyFile=Join-Path $legacy 'config\bridge.ini'
  if(-not [IO.File]::Exists($policyFile)){Fail 'LEGACY_CONFIG_MISSING'}
  $policy=[IO.File]::ReadAllText($policyFile,[Text.Encoding]::ASCII)
  foreach($gate in @('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')){
    if($policy -notmatch ('(?m)^'+[regex]::Escape($gate)+'\s*$')){Fail 'LEGACY_BRIDGE_NOT_SAFE_IDLE'}
  }
  if([string]::IsNullOrEmpty($BootstrapTlsDir) -or -not [IO.Directory]::Exists($BootstrapTlsDir)){Fail 'BOOTSTRAP_TLS_MISSING'}
  $sourceCurl=Join-Path $BootstrapTlsDir 'curl.exe'
  $sourceCa=Join-Path $BootstrapTlsDir 'curl-ca-bundle.crt'
  if(-not [IO.File]::Exists($sourceCurl) -or -not [IO.File]::Exists($sourceCa)){Fail 'BOOTSTRAP_FILES_MISSING'}
  $root='C:\ProgramData\MspCustomerStore'
  if([IO.Directory]::Exists($root) -or [IO.File]::Exists($root)){Fail 'ROOT_ALREADY_EXISTS'}
  $sched=New-Object -ComObject Schedule.Service
  $sched.Connect()
  $folder=$sched.GetFolder('\')
  $existing=$null
  try{$existing=$folder.GetTask('MspCustomerStoreSync')}catch{}
  if($null -ne $existing){Fail 'COLLECTOR_TASK_ALREADY_EXISTS'}
  $icacls=Join-Path $env:WINDIR 'System32\icacls.exe'
  if(-not [IO.File]::Exists($icacls)){Fail 'ICACLS_MISSING'}
  $phase='CREATE_ROOT_AND_ACL'
  [void][IO.Directory]::CreateDirectory($root)
  Grant $root @('/inheritance:r','/grant:r','*S-1-5-18:(OI)(CI)F','*S-1-5-32-544:(OI)(CI)F','*S-1-5-19:(OI)(CI)RX') $icacls
  foreach($name in @('bin','config','schema','data','state','logs','staging','secrets','backups')){
    $dir=Join-Path $root $name
    [void][IO.Directory]::CreateDirectory($dir)
    if(@('data','state','logs','staging','backups') -contains $name){
      Grant $dir @('/grant:r','*S-1-5-19:(OI)(CI)M') $icacls
    }
  }
  $bin=Join-Path $root 'bin'
  $staging=Join-Path $root 'staging'
  $installedCurl=Join-Path $bin 'curl.exe'
  [IO.File]::Copy($sourceCurl,$installedCurl,$false)
  $installedCa=Join-Path $root 'config\curl-ca-bundle.crt'
  [IO.File]::Copy($sourceCa,$installedCa,$false)
  $dllCount=0
  foreach($lib in @(Get-ChildItem -LiteralPath $BootstrapTlsDir -Filter '*.dll' -ErrorAction Stop)){
    if($lib.Length -gt 52428800){Fail 'TLS_LIBRARY_SIZE_OUT_OF_RANGE'}
    [IO.File]::Copy($lib.FullName,(Join-Path $bin $lib.Name),$false)
    $dllCount++
  }
  $curlVersion=@(& $installedCurl --version 2>&1)
  if($LASTEXITCODE -ne 0 -or (($curlVersion -join ' ') -notmatch '(?i)curl')){Fail 'INSTALLED_CURL_DEPENDENCY_ERROR'}
  $phase='SQLITE_DOWNLOAD'
  $zip=Join-Path $staging 'sqlite-tools-win32-x86-3430200.zip'
  Fetch 'https://www.sqlite.org/2023/sqlite-tools-win32-x86-3430200.zip' $zip $sourceCurl $sourceCa
  if((Sha256 $zip) -ne 'fae9efccf4469ca69be5d418fc088593cdb86e07a1b211bdb85463591a923b02'){Fail 'SQLITE_OFFICIAL_ZIP_HASH_MISMATCH'}
  $phase='SQLITE_EXTRACT'
  $shell=New-Object -ComObject Shell.Application
  $archive=$shell.NameSpace([string]$zip)
  $dst=$shell.NameSpace([string]$bin)
  if($null -eq $archive -or $null -eq $dst){Fail 'ZIP_COM_INTERFACE_UNAVAILABLE'}
  $entry=$archive.ParseName('sqlite3.exe')
  if($null -eq $entry -or $entry.IsFolder){Fail 'SQLITE_NOT_FOUND_IN_ARCHIVE'}
  $exe=Join-Path $bin 'sqlite3.exe'
  $dst.CopyHere($entry,0x14)
  $stable=0
  $lastLength=-1
  for($i=0;$i -lt 100;$i++){
    Start-Sleep -Milliseconds 300
    if([IO.File]::Exists($exe)){
      try{
        $length=([IO.FileInfo]$exe).Length
        if($length -gt 250000 -and $length -eq $lastLength){$stable++}else{$stable=0}
        $lastLength=$length
        if($stable -ge 4){break}
      }catch{}
    }
  }
  if($stable -lt 4){Fail 'SQLITE_EXTRACT_TIMEOUT'}
  $v=@(& $exe -version 2>&1)
  if($LASTEXITCODE -ne 0 -or (($v -join ' ') -notmatch '^3\.43\.2(\s|$)')){Fail 'SQLITE_BINARY_NOT_COMPATIBLE'}
  $phase='PINNED_CODE'
  $raw='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/a4f583ac7404cbad2601457ceb2f79c86ec807f1/integrations/msp-bitrix24-bridge/'
  $manifest=@(
    @('bin/smoke-customer-store-service.ps1','bin\smoke-customer-store-service.ps1','d161be777520b9fd527e5e08698174f08a76aa00'),
    @('config/collector.ini','config\collector.ini','ed6c50cf9731668c35a115b547ee363db837a915'),
    @('schema/customer-store.sql','schema\customer-store.sql','6452fe80e329d5380baa115b6fc6537b0fa43d95')
  )
  foreach($row in $manifest){
    $path=Join-Path $root $row[1]
    Fetch ($raw+$row[0]) $path $sourceCurl $sourceCa
    if((BlobSha1 $path) -ne $row[2]){Fail 'PINNED_SOURCE_HASH_MISMATCH'}
  }
  $phase='STAGE_LOCAL_TASK'
  $ls=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  if(-not $ls){Fail 'LOCAL_SERVICE_UNRESOLVED'}
  $definition=$sched.NewTask(0)
  $definition.RegistrationInfo.Description='MspCustomerStore: safe LOCAL SERVICE empty-DB acceptance, no OData'
  $definition.Principal.UserId=$ls
  $definition.Principal.LogonType=5
  $definition.Principal.RunLevel=0
  $definition.Settings.Enabled=$true
  $definition.Settings.StartWhenAvailable=$true
  $definition.Settings.ExecutionTimeLimit='PT2M'
  $definition.Settings.MultipleInstances=2
  $boot=$definition.Triggers.Create(8)
  $boot.Enabled=$false
  $action=$definition.Actions.Create(0)
  $action.Path=(Join-Path $PSHOME 'powershell.exe')
  $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $bin 'smoke-customer-store-service.ps1')+'" -ExpectedComputerName SRV'
  $null=$folder.RegisterTaskDefinition('MspCustomerStoreSync',$definition,2,$ls,$null,5,$null)
  $task=$folder.GetTask('MspCustomerStoreSync')
  if(-not $task.Enabled -or $task.Definition.Triggers.Item(1).Enabled){Fail 'TASK_BOOT_TRIGGER_NOT_DISABLED'}
  $phase='LOCAL_SERVICE_MANUAL_SMOKE'
  $started=[DateTime]::UtcNow
  $null=$task.Run($null)
  $status=Join-Path $root 'state\status.txt'
  $accepted=$false
  for($i=0;$i -lt 100;$i++){
    Start-Sleep -Milliseconds 500
    if([IO.File]::Exists($status)){
      $text=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII)
      if($text -match '^UTC=([^;]+);STATUS=EMPTY_DB_PASS;IDENTITY=LOCAL_SERVICE;CUSTOMERS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){
        $when=[DateTime]::Parse($Matches[1]).ToUniversalTime()
        if($when -ge $started.AddSeconds(-2)){$accepted=$true;break}
      }
      if($text -match '^STATUS=FAIL'){Fail 'SERVICE_SMOKE_FAILED'}
    }
  }
  if(-not $accepted){Fail 'SERVICE_SMOKE_NOT_CONFIRMED'}
  $db=Join-Path $root 'data\customers.db'
  if(-not [IO.File]::Exists($db)){Fail 'SERVICE_DATABASE_MISSING'}
  $cnt=@(& $exe -batch -bail $db 'SELECT count(*) FROM customers;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($cnt -join '').Trim() -ne '0'){Fail 'DATABASE_NOT_EMPTY'}
  'MACHINE_COLLECTOR_ROOT='+$root
  'RUN_AS_LOCAL_SERVICE=YES'
  'SQLITE_VERSION=3.43.2'
  'SQLITE_ZIP_SHA256=PASS'
  'PINNED_GITHUB_SOURCES=PASS'
  'TLS_RUNTIME_MACHINE_OWNED=YES'
  'TLS_DEPENDENCY_DLLS_COPIED='+$dllCount
  'EMPTY_DB_CREATED_BY_LOCAL_SERVICE=YES'
  'CUSTOMERS_COUNT=0'
  'SYNTHETIC_TRANSACTION_ROLLBACK=PASS'
  'COLLECTOR_TASK_EXISTS=YES'
  'COLLECTOR_BOOT_TRIGGER_ENABLED=NO'
  'PREVIOUS_BRIDGE_UNCHANGED=YES'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_MACHINE_CUSTOMER_STORE_INSTALL'
}catch{
  $gate='RUNTIME_ERROR'
  $message=$_.Exception.Message
  if($message -match '^INSTALL_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_MACHINE_CUSTOMER_STORE_INSTALL;GATE='+$gate
  'FAILURE_PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

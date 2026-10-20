#requires -version 2
# One-time 10-customer pilot; only local machine-owned files + TEST 1C GET.
# Registers an on-demand LOCAL SERVICE task; no startup or existing task changes.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Why){throw ('PILOT_SETUP_'+$Why)}
function Sha([string]$File){
  $s=New-Object Security.Cryptography.SHA256Managed
  try{$d=$s.ComputeHash([IO.File]::ReadAllBytes($File));return ([BitConverter]::ToString($d)).Replace('-','').ToLowerInvariant()}finally{$s.Clear()}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
  $who=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $legacy='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
  $config=Join-Path $root 'config\collector.ini'
  $db=Join-Path $root 'data\customers.db'
  $sqlite=Join-Path $root 'bin\sqlite3.exe'
  $curl=Join-Path $root 'bin\curl.exe'
  $ca=Join-Path $root 'config\curl-ca-bundle.crt'
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $worker=Join-Path $root 'bin\pilot-machine-customer-store-10.ps1'
  $state=Join-Path $root 'state\customer-pilot10-status.txt'
  foreach($file in @($legacy,$config,$db,$sqlite,$curl,$ca,$secret)){
    if(-not [IO.File]::Exists($file)){Fail 'MACHINE_COMPONENT_MISSING'}
    if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
  }
  if([IO.File]::Exists($worker) -or [IO.File]::Exists($state)){Fail 'PILOT_ALREADY_STAGED'}
  foreach($item in @(@($config,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),@($legacy,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')))){
    $contents=[IO.File]::ReadAllText([string]$item[0],[Text.Encoding]::ASCII)
    foreach($flag in $item[1]){if($contents -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_VIOLATION'}}
  }
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $task=$folder.GetTask('MspCustomerStoreSync')
  if($null -eq $task){Fail 'COLLECTOR_TASK_MISSING'}
  $runAs=$task.Definition.Principal.UserId
  if($runAs -eq 'S-1-5-19'){$sid=$runAs}else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $runAs).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($sid -ne 'S-1-5-19'){Fail 'COLLECTOR_TASK_NOT_SERVICE'}
  foreach($trigger in $task.Definition.Triggers){if($trigger.Enabled){Fail 'COLLECTOR_STARTUP_ALREADY_ENABLED'}}
  $existing=$null
  try{$existing=$folder.GetTask('MspCustomerStorePilot10')}catch{}
  if($null -ne $existing){Fail 'PILOT_TASK_ALREADY_EXISTS'}
  $before=@(& $sqlite -batch -bail $db 'SELECT count(*) FROM customers;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($before -join '').Trim() -ne '0'){Fail 'CUSTOMERS_DB_NOT_EMPTY'}
  $quick=@(& $sqlite -batch -bail $db 'PRAGMA quick_check;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($quick -join '').Trim() -ne 'ok'){Fail 'CUSTOMERS_DB_INTEGRITY_BAD'}
  $phase='DOWNLOAD_WORKER'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/c6d8f9dfd75a4de30f4ff5f129ec7409bfbbc1dd/integrations/msp-bitrix24-bridge/bin/pilot-machine-customer-store-10.ps1'
  & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Fail 'WORKER_DOWNLOAD_FAILED'}
  if((Sha $worker) -ne '006b1e02cdfcb1942cb90c5ecb2414c905efe3289deaac5d00040ec90bdf6f6f'){Fail 'WORKER_HASH_MISMATCH'}
  $parseErrors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$parseErrors)
  if($parseErrors -and $parseErrors.Count -gt 0){Fail 'PS2_WORKER_PARSE_FAILED'}
  'PILOT_WORKER_SHA256=PASS'
  $phase='RUN_ONCE_AS_SERVICE'
  $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $def=$scheduler.NewTask(0)
  $def.RegistrationInfo.Description='One-time LOCAL SERVICE read-only 1C -> 10 local SQLite buyer rows pilot'
  $def.Principal.UserId=$service
  $def.Principal.LogonType=5
  $def.Principal.RunLevel=0
  $def.Settings.Enabled=$true
  $def.Settings.ExecutionTimeLimit='PT3M'
  $def.Settings.MultipleInstances=2
  $action=$def.Actions.Create(0)
  $action.Path=Join-Path $PSHOME 'powershell.exe'
  $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
  $null=$folder.RegisterTaskDefinition('MspCustomerStorePilot10',$def,2,$service,$null,5,$null)
  $pilot=$folder.GetTask('MspCustomerStorePilot10')
  if($pilot.Definition.Triggers.Count -ne 0){Fail 'PILOT_TASK_HAS_TRIGGER'}
  $start=[DateTime]::UtcNow
  $null=$pilot.Run($null)
  $passed=$false
  for($i=0;$i -lt 150;$i++){
    Start-Sleep -Milliseconds 500
    if(-not [IO.File]::Exists($state)){continue}
    $line=[IO.File]::ReadAllText($state,[Text.Encoding]::ASCII).Trim()
    if($line -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
      'PILOT_FAILURE_GATE='+$Matches[1]
      'PILOT_FAILURE_PHASE='+$Matches[2]
      Fail 'SERVICE_PILOT_FAILED'
    }
    if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;ROWS=10;UNIQUE_GUIDS=10;DB_INTEGRITY=ok;ONEC_WRITES=0;BITRIX_CALLS=0$'){
      $utc=[DateTime]::Parse($Matches[1]).ToUniversalTime()
      if($utc -ge $start.AddSeconds(-2)){$passed=$true;break}
    }
  }
  if(-not $passed){Fail 'SERVICE_PILOT_UNCONFIRMED'}
  $phase='SQLITE_BACKREAD'
  $recount=@(& $sqlite -batch -bail $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;" 2>&1)
  if($LASTEXITCODE -ne 0 -or ($recount -join '').Trim() -ne '10:10'){Fail 'PILOT_DB_COUNT_MISMATCH'}
  $integrity=@(& $sqlite -batch -bail $db 'PRAGMA quick_check;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($integrity -join '').Trim() -ne 'ok'){Fail 'PILOT_DB_INTEGRITY_FAILED'}
  $phase='REMOVE_ONE_TIME_TASK'
  $folder.DeleteTask('MspCustomerStorePilot10',0)
  'LOCAL_SERVICE_PILOT=PASS'
  'PILOT_ROWS=10'
  'PILOT_UNIQUE_GUIDS=10'
  'DB_QUICK_CHECK=ok'
  'PILOT_ONE_TIME_TASK_REMOVED=YES'
  'COLLECTOR_AUTOSTART=OFF'
  'EXISTING_TASKS_UNCHANGED=YES'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_FIRST10_ACCEPTANCE'
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^PILOT_SETUP_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_FIRST10_ACCEPTANCE;GATE='+$gate+';PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

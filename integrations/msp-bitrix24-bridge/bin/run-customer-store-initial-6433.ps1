#requires -version 2
# One-time acceptance launch of 6433-buyer initial SQLite load under LOCAL SERVICE.
# Never changes existing boot schedules, 1C TEST, Bitrix or other tasks.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('INITIAL_'+$Code)}
function Sha([string]$File){
  $h=New-Object Security.Cryptography.SHA256Managed
  try{$digest=$h.ComputeHash([IO.File]::ReadAllBytes($File));return ([BitConverter]::ToString($digest)).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $conf=Join-Path $root 'config\collector.ini'
  $legacy='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
  $sqlite=Join-Path $root 'bin\sqlite3.exe'
  $db=Join-Path $root 'data\customers.db'
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $pilot=Join-Path $root 'state\customer-pilot10-status.txt'
  $status=Join-Path $root 'state\customer-initial-load-status.txt'
  $worker=Join-Path $root 'bin\initial-load-customers-6433.ps1'
  $curl=Join-Path $root 'bin\curl.exe'
  $ca=Join-Path $root 'config\curl-ca-bundle.crt'
  foreach($f in @($conf,$legacy,$sqlite,$db,$secret,$pilot,$curl,$ca)){
    if(-not [IO.File]::Exists($f)){Fail 'MACHINE_COMPONENT_MISSING'}
    if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'MACHINE_COMPONENT_REPARSE'}
  }
  if([IO.File]::Exists($worker) -or [IO.File]::Exists($status)){Fail 'INITIAL_LOAD_ALREADY_STAGED'}
  foreach($bundle in @(@($conf,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),@($legacy,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')))){
    $settings=[IO.File]::ReadAllText([string]$bundle[0],[Text.Encoding]::ASCII)
    foreach($flag in $bundle[1]){
      if($settings -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_CONFIG_INVALID'}
    }
  }
  $proof=[IO.File]::ReadAllText($pilot,[Text.Encoding]::ASCII).Trim()
  if($proof -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;ROWS=10;UNIQUE_GUIDS=10;DB_INTEGRITY=ok;ONEC_WRITES=0;BITRIX_CALLS=0$'){Fail 'TEN_ROW_PILOT_NOT_ACCEPTED'}
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $main=$folder.GetTask('MspCustomerStoreSync')
  if($null -eq $main){Fail 'COLLECTOR_TASK_MISSING'}
  $runAs=$main.Definition.Principal.UserId
  if($runAs -eq 'S-1-5-19'){$sid=$runAs}else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $runAs).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($sid -ne 'S-1-5-19'){Fail 'COLLECTOR_TASK_IDENTITY_INVALID'}
  foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'COLLECTOR_AUTO_START_NOT_SAFE'}}
  $oldPilot=$null
  try{$oldPilot=$folder.GetTask('MspCustomerStorePilot10')}catch{}
  if($null -ne $oldPilot){Fail 'TEN_ROW_PILOT_TASK_STILL_PRESENT'}
  $prior=$null
  try{$prior=$folder.GetTask('MspCustomerStoreInitial6433')}catch{}
  if($null -ne $prior){Fail 'INITIAL_LOAD_TASK_ALREADY_EXISTS'}
  $before=@(& $sqlite -batch -bail $db 'SELECT count(*) FROM customers;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($before -join '').Trim() -ne '10'){Fail 'EXPECTED_TEN_PILOT_ROWS'}
  $runs=@(& $sqlite -batch -bail $db 'SELECT count(*) FROM scan_runs;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($runs -join '').Trim() -ne '0'){Fail 'EXISTING_SCAN_RUNS_PRESENT'}
  $quick=@(& $sqlite -batch -bail $db 'PRAGMA quick_check;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($quick -join '').Trim() -ne 'ok'){Fail 'DATABASE_INTEGRITY_BAD'}
  $phase='FETCH_HASHED_WORKER'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/eb29600a875df2c27f8b6018b2ad4d8e0122c559/integrations/msp-bitrix24-bridge/bin/initial-load-customers-6433.ps1'
  & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Fail 'WORKER_DOWNLOAD_FAILED'}
  if((Sha $worker) -ne 'a06c3c2155434557e9fb106dad820588aefedcf22afec72f9a8ec56ae7eabc98'){Fail 'WORKER_SHA256_INVALID'}
  $errors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
  if($errors -and $errors.Count -gt 0){Fail 'WORKER_PS2_PARSE_FAILED'}
  'INITIAL_WORKER_SHA256=PASS'
  $phase='LOCAL_SERVICE_LAUNCH'
  $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $taskDef=$scheduler.NewTask(0)
  $taskDef.RegistrationInfo.Description='One-time local TEST 1C 6433 buyers -> SRV SQLite under LOCAL SERVICE'
  $taskDef.Principal.UserId=$service
  $taskDef.Principal.LogonType=5
  $taskDef.Principal.RunLevel=0
  $taskDef.Settings.Enabled=$true
  $taskDef.Settings.ExecutionTimeLimit='PT20M'
  $taskDef.Settings.MultipleInstances=2
  $action=$taskDef.Actions.Create(0)
  $action.Path=Join-Path $PSHOME 'powershell.exe'
  $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
  $null=$folder.RegisterTaskDefinition('MspCustomerStoreInitial6433',$taskDef,2,$service,$null,5,$null)
  $task=$folder.GetTask('MspCustomerStoreInitial6433')
  if($task.Definition.Triggers.Count -ne 0){Fail 'TEMPORARY_TASK_HAS_AUTO_TRIGGER'}
  $started=[DateTime]::UtcNow
  $null=$task.Run($null)
  $passed=$false
  $pageCount=0
  $legal=0
  $person=0
  $review=0
  for($i=0;$i -lt 1800;$i++){
    Start-Sleep -Milliseconds 500
    if(-not [IO.File]::Exists($status)){continue}
    $line=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII).Trim()
    if($line -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
      'FULL_LOAD_FAILURE_GATE='+$Matches[1]
      'FULL_LOAD_FAILURE_PHASE='+$Matches[2]
      Fail 'LOCAL_SERVICE_INITIAL_LOAD_FAILED'
    }
    if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;ROWS=6433;UNIQUE_GUIDS=6433;PAGES=([0-9]+);LEGAL=([0-9]+);PERSON=([0-9]+);REVIEW=([0-9]+);DB_INTEGRITY=ok;ONEC_WRITES=0;BITRIX_CALLS=0$'){
      $when=[DateTime]::Parse($Matches[1]).ToUniversalTime()
      if($when -ge $started.AddSeconds(-2)){
        $pageCount=[int]::Parse($Matches[2])
        $legal=[int]::Parse($Matches[3])
        $person=[int]::Parse($Matches[4])
        $review=[int]::Parse($Matches[5])
        $passed=$true
        break
      }
    }
  }
  if(-not $passed){Fail 'LOAD_STATUS_NOT_CONFIRMED'}
  if(($legal+$person+$review) -ne 6433 -or $pageCount -ne 65){Fail 'SOURCE_AGGREGATES_INVALID'}
  $phase='BACKREAD'
  $summary=@(& $sqlite -batch -bail $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;" 2>&1)
  if($LASTEXITCODE -ne 0 -or ($summary -join '').Trim() -ne '6433:6433'){Fail 'DATABASE_ROWS_NOT_6433'}
  $kinds=@(& $sqlite -batch -bail $db "SELECT sum(onec_type='LEGAL') || ':' || sum(onec_type='PERSON') || ':' || sum(onec_type='REVIEW') FROM customers;" 2>&1)
  if($LASTEXITCODE -ne 0 -or ($kinds -join '').Trim() -ne ($legal+':'+$person+':'+$review)){Fail 'DATABASE_TYPE_COUNTS_MISMATCH'}
  $q=@(& $sqlite -batch -bail $db 'PRAGMA quick_check;' 2>&1)
  if($LASTEXITCODE -ne 0 -or ($q -join '').Trim() -ne 'ok'){Fail 'POST_IMPORT_DB_CORRUPT'}
  $phase='DELETE_TEMP_TASK'
  $folder.DeleteTask('MspCustomerStoreInitial6433',0)
  'S3_INITIAL_LOAD_LOCAL_SERVICE=PASS'
  'S3_ROWS=6433'
  'S3_UNIQUE_GUIDS=6433'
  'S3_NEW_GUIDS=6423'
  'S3_EXISTING_PILOT_GUIDS=10'
  'S3_PAGES='+$pageCount
  'S3_LEGAL='+$legal
  'S3_PERSON='+$person
  'S3_REVIEW='+$review
  'DB_QUICK_CHECK=ok'
  'TEMP_TASK_DELETED=YES'
  'COLLECTOR_BOOT_AUTOSTART=OFF'
  'OTHER_TASKS_CHANGED=NO'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_INITIAL_LOAD_ACCEPTANCE'
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^INITIAL_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_INITIAL_LOAD_ACCEPTANCE;GATE='+$gate+';PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

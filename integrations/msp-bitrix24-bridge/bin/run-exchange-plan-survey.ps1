#requires -version 2
# One-shot metadata-only ExchangePlan survey under LOCAL SERVICE.
# Existing machine-owned customer SQLite stays unchanged. No 1C/Bitrix writes.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('SURVEY_'+$Code)}
function Sha([string]$File){
  $sha=New-Object Security.Cryptography.SHA256Managed
  try{$hash=$sha.ComputeHash([IO.File]::ReadAllBytes($File));return ([BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant()}
  finally{$sha.Clear()}
}
function Q([string]$Exe,[string]$Db,[string]$Text){
  $result=@(& $Exe -readonly -batch -bail $Db $Text 2>&1)
  if($LASTEXITCODE -ne 0){Fail 'READONLY_DB_QUERY_FAILED'}
  return ($result -join '').Trim()
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
  $win=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $win
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $exe=Join-Path $root 'bin\sqlite3.exe'
  $db=Join-Path $root 'data\customers.db'
  $accept=Join-Path $root 'state\customer-initial-load-accepted.txt'
  $status=Join-Path $root 'state\exchange-plan-metadata-s4.txt'
  $worker=Join-Path $root 'bin\survey-exchange-plan-metadata-service.ps1'
  $curl=Join-Path $root 'bin\curl.exe'
  $ca=Join-Path $root 'config\curl-ca-bundle.crt'
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $config=Join-Path $root 'config\collector.ini'
  $legacy='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
  foreach($file in @($exe,$db,$accept,$curl,$ca,$secret,$config,$legacy)){
    if(-not [IO.File]::Exists($file)){Fail 'MACHINE_COMPONENT_MISSING'}
    if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
  }
  if([IO.File]::Exists($worker) -or [IO.File]::Exists($status)){Fail 'SURVEY_PREVIOUS_STATE_EXISTS'}
  $receipt=[IO.File]::ReadAllText($accept,[Text.Encoding]::ASCII)
  if($receipt -notmatch ';ACCEPTANCE=PASS;IDENTITY=LOCAL_SERVICE;ROWS=6433;UNIQUE_GUIDS=6433;ACTIVE=6433;LEGAL=1941;PERSON=4486;REVIEW=6;INITIAL_RUNS=1;DB_INTEGRITY=ok;TEMP_TASK_REMOVED=YES;AUTO_START=OFF;ONEC_WRITES=0;BITRIX_CALLS=0$'){
    Fail 'S3_ACCEPTANCE_INVALID'
  }
  foreach($pair in @(
    @($config,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),
    @($legacy,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0'))
  )){
    $flags=[IO.File]::ReadAllText([string]$pair[0],[Text.Encoding]::ASCII)
    foreach($f in $pair[1]){
      if($flags -notmatch ('(?m)^'+[regex]::Escape($f)+'\s*$')){Fail 'SAFE_IDLE_CHANGED'}
    }
  }
  if((Q $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'DB_COUNT_CHANGED'}
  if((Q $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY_CHANGED'}
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $main=$folder.GetTask('MspCustomerStoreSync')
  if($null -eq $main){Fail 'MAIN_TASK_MISSING'}
  $user=$main.Definition.Principal.UserId
  if($user -eq 'S-1-5-19'){$sid=$user}else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $user).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($sid -ne 'S-1-5-19'){Fail 'MAIN_TASK_WRONG_IDENTITY'}
  foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_TASK_AUTOSTART_ENABLED'}}
  $prior=$null
  try{$prior=$folder.GetTask('MspCustomerStoreExchangeSurvey')}catch{}
  if($null -ne $prior){Fail 'SURVEY_TASK_ALREADY_EXISTS'}
  $phase='DOWNLOAD_PINNED_GET_PROBE'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/560a2e3e11b53c9c7aecc723761682d24010d2aa/integrations/msp-bitrix24-bridge/bin/survey-exchange-plan-metadata-service.ps1'
  & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Fail 'PROBE_DOWNLOAD_FAILED'}
  if((Sha $worker) -ne '492272aa431752620d2a5266166e3387c68bcc9b7748854cf2a5cb01cb94dc79'){Fail 'PROBE_SHA256_MISMATCH'}
  $errors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
  if($errors -and $errors.Count -gt 0){Fail 'PROBE_PS2_PARSE_FAILED'}
  'S4_GET_PROBE_SHA256=PASS'
  $phase='CREATE_MANUAL_SERVICE_TASK'
  $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $taskDef=$scheduler.NewTask(0)
  $taskDef.RegistrationInfo.Description='One-time LOCAL SERVICE read-only OData metadata survey, no database update'
  $taskDef.Principal.UserId=$service
  $taskDef.Principal.LogonType=5
  $taskDef.Principal.RunLevel=0
  $taskDef.Settings.Enabled=$true
  $taskDef.Settings.ExecutionTimeLimit='PT3M'
  $taskDef.Settings.MultipleInstances=2
  $action=$taskDef.Actions.Create(0)
  $action.Path=Join-Path $PSHOME 'powershell.exe'
  $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
  $null=$folder.RegisterTaskDefinition('MspCustomerStoreExchangeSurvey',$taskDef,2,$service,$null,5,$null)
  $task=$folder.GetTask('MspCustomerStoreExchangeSurvey')
  if($task.Definition.Triggers.Count -ne 0){Fail 'TASK_HAS_AUTOMATIC_TRIGGER'}
  $started=[DateTime]::UtcNow
  $null=$task.Run($null)
  $ok=$false
  $planCount=0
  $entityCount=0
  $select='False'
  $confirm='False'
  for($i=0;$i -lt 240;$i++){
    Start-Sleep -Milliseconds 500
    if(-not [IO.File]::Exists($status)){continue}
    $lines=[IO.File]::ReadAllLines($status,[Text.Encoding]::ASCII)
    if($lines.Length -lt 1){continue}
    $line=$lines[0].Trim()
    if($line -match '^STATUS=FAIL;PHASE=([A-Z0-9_]+);GATE=([A-Z0-9_]+)$'){
      'S4_FAILURE_PHASE='+$Matches[1]
      'S4_FAILURE_GATE='+$Matches[2]
      Fail 'SERVICE_METADATA_PROBE_FAILED'
    }
    if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;HTTP=200;ENTITY_SETS=([0-9]+);EXCHANGE_PLANS=([0-9]+);SELECTCHANGES_DECLARED=(True|False);CONFIRMCHANGES_DECLARED=(True|False);ONEC_WRITES=0;BITRIX_CALLS=0$'){
      $when=[DateTime]::Parse($Matches[1]).ToUniversalTime()
      if($when -ge $started.AddSeconds(-2)){
        $entityCount=[int]::Parse($Matches[2])
        $planCount=[int]::Parse($Matches[3])
        $select=$Matches[4]
        $confirm=$Matches[5]
        if($planCount -gt 100 -or $lines.Length -ne ($planCount+1)){Fail 'METADATA_LIST_LENGTH_INVALID'}
        for($j=1;$j -lt $lines.Length;$j++){
          if($lines[$j] -notmatch ('^PLAN_{0:D3}=[ -~]{1,1100}$' -f $j)){Fail 'PLAN_LINE_INVALID'}
        }
        $ok=$true
        break
      }
    }
  }
  if(-not $ok){Fail 'METADATA_PROOF_TIMEOUT'}
  $phase='DB_READBACK_UNCHANGED'
  if((Q $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'S3_DB_CHANGED_DURING_PROBE'}
  if((Q $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'S3_DB_INTEGRITY_CHANGED'}
  $phase='DELETE_ONE_TIME_TASK'
  $folder.DeleteTask('MspCustomerStoreExchangeSurvey',0)
  'S4_METADATA_HTTP=200'
  'S4_ENTITY_SET_COUNT='+$entityCount
  'S4_EXCHANGE_PLAN_SET_COUNT='+$planCount
  'S4_SELECTCHANGES_DECLARED='+$select
  'S4_CONFIRMCHANGES_DECLARED='+$confirm
  for($j=1;$j -lt $lines.Length;$j++){$lines[$j]}
  'S4_TEMP_TASK_DELETED=YES'
  'S4_6433_CUSTOMER_DB_UNCHANGED=YES'
  'S4_MAIN_COLLECTOR_AUTOSTART=OFF'
  'S4_REGISTERED_DELTA=NOT_YET_PROVEN'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_ONEC_OPTION_B_READONLY_CAPABILITY_SURVEY'
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^SURVEY_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_ONEC_OPTION_B_READONLY_CAPABILITY_SURVEY;GATE='+$gate+';PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

#requires -version 2
# S4 V2 one-shot admin runner: LOCAL SERVICE reads TEST NewBase OData $metadata.
# No production calls, no customer data export, no SQLite/1C/Bitrix writes.
# Does not modify or delete legacy S4 V1 or MspCustomerStoreSync tasks.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('S4V2_'+$Code)}
function Sha([string]$Path){
  $s=New-Object Security.Cryptography.SHA256Managed
  try{return ([BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
  finally{$s.Clear()}
}
function Query([string]$Exe,[string]$Db,[string]$Sql){
  $r=@(& $Exe -readonly -batch -bail $Db $Sql 2>&1)
  if($LASTEXITCODE -ne 0){Fail 'SQLITE_READONLY_FAILED'}
  return ($r -join '').Trim()
}
function NoEnabledTriggers($Task,[string]$Label){
  foreach($trigger in $Task.Definition.Triggers){
    if($trigger.Enabled){Fail ($Label+'_TRIGGER_ENABLED')}
  }
}
function ServiceSid($Task){
  $id=[string]$Task.Definition.Principal.UserId
  if($id -eq 'S-1-5-19'){return $id}
  return (New-Object Security.Principal.NTAccount -ArgumentList $id).Translate([Security.Principal.SecurityIdentifier]).Value
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $exe=Join-Path $root 'bin\sqlite3.exe'
  $db=Join-Path $root 'data\customers.db'
  $curl=Join-Path $root 'bin\curl.exe'
  $ca=Join-Path $root 'config\curl-ca-bundle.crt'
  $ini=Join-Path $root 'config\collector.ini'
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $worker=Join-Path $root 'bin\survey-exchange-plan-metadata-service-v2.ps1'
  $status=Join-Path $root 'state\exchange-plan-metadata-s4-v2.txt'
  $oldStatus=Join-Path $root 'state\exchange-plan-metadata-s4.txt'
  foreach($f in @($exe,$db,$curl,$ca,$ini,$secret,$oldStatus)){
    if(-not [IO.File]::Exists($f)){Fail 'MISSING_COMPONENT'}
    if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
  }
  if([IO.File]::Exists($status) -or [IO.File]::Exists($worker)){Fail 'V2_PREVIOUS_STATE_PRESENT'}
  if([IO.File]::ReadAllText($oldStatus,[Text.Encoding]::ASCII) -notmatch '^STATUS=FAIL;PHASE=PARSE_EXCHANGE_PLANS;GATE=RUNTIME_ERROR\s*$'){
    Fail 'V1_FAILURE_RECEIPT_CHANGED'
  }
  $flags=[IO.File]::ReadAllText($ini,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($flags -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'COLLECTOR_SAFE_IDLE_CHANGED'}
  }
  if((Query $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){
    Fail 'SOURCE_SNAPSHOT_COUNT_CHANGED'
  }
  if((Query $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'SOURCE_DB_INTEGRITY_FAILED'}
  $phase='CHECK_TASK_ISOLATION'
  $sch=New-Object -ComObject Schedule.Service
  $sch.Connect()
  $folder=$sch.GetFolder('\')
  $main=$folder.GetTask('MspCustomerStoreSync')
  if($null -eq $main){Fail 'MAIN_TASK_MISSING'}
  if((ServiceSid $main) -ne 'S-1-5-19'){Fail 'MAIN_TASK_IDENTITY_CHANGED'}
  NoEnabledTriggers $main 'MAIN'
  if([int]$main.State -eq 4){Fail 'MAIN_TASK_RUNNING'}
  $old=$folder.GetTask('MspCustomerStoreExchangeSurvey')
  if($null -eq $old){Fail 'V1_TASK_MISSING'}
  NoEnabledTriggers $old 'V1'
  if([int]$old.State -eq 4){Fail 'V1_TASK_RUNNING'}
  $taskName='MspCustomerStoreExchangeSurveyV2'
  $existing=$null
  try{$existing=$folder.GetTask($taskName)}catch{}
  if($null -ne $existing){Fail 'V2_TASK_ALREADY_PRESENT'}
  $phase='GET_PINNED_SCRIPT'
  $commit='f41bf94ed4187fcc41a5bc1e8d09c86a86e333d5'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/'+$commit+'/integrations/msp-bitrix24-bridge/bin/survey-exchange-plan-metadata-service-v2.ps1'
  & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Fail 'DOWNLOAD_FAILED'}
  if((Sha $worker) -ne '945d5d18418ee5b289f275f1618e3f5a41aab6a94781b01fa3a9d5b8d6d4c57e'){
    Fail 'WORKER_SHA256_MISMATCH'
  }
  $err=$null
  $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::UTF8),[ref]$err)
  if($err -and $err.Count -gt 0){Fail 'WORKER_PARSE_FAILED'}
  'S4_V2_WORKER_SHA256=PASS'
  'S4_V2_WORKER_PS2_PARSE=PASS'
  $phase='REGISTER_TRIGGERLESS_TASK'
  $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $def=$sch.NewTask(0)
  $def.RegistrationInfo.Description='S4 V2 one-shot TEST NewBase OData metadata GET only'
  $def.Principal.UserId=$service
  $def.Principal.LogonType=5
  $def.Principal.RunLevel=0
  $def.Settings.Enabled=$true
  $def.Settings.ExecutionTimeLimit='PT3M'
  $def.Settings.MultipleInstances=2
  $action=$def.Actions.Create(0)
  $action.Path=Join-Path $PSHOME 'powershell.exe'
  $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
  $null=$folder.RegisterTaskDefinition($taskName,$def,2,$service,$null,5,$null)
  $task=$folder.GetTask($taskName)
  if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){Fail 'V2_TASK_INVALID'}
  if((ServiceSid $task) -ne 'S-1-5-19'){Fail 'V2_IDENTITY_INVALID'}
  if([int]$task.Definition.Actions.Count -ne 1){Fail 'V2_TASK_ACTION_INVALID'}
  $phase='ONE_SHOT_TEST_METADATA'
  $started=[DateTime]::UtcNow
  $null=$task.Run($null)
  $accepted=$false
  $entityCount=0;$planCount=0;$select='';$notify=''
  $readLines=$null
  for($i=0;$i -lt 240;$i++){
    Start-Sleep -Milliseconds 500
    if(-not [IO.File]::Exists($status)){continue}
    $readLines=[IO.File]::ReadAllLines($status,[Text.Encoding]::ASCII)
    if($readLines.Length -lt 1){continue}
    $line=$readLines[0].Trim()
    if($line -match '^STATUS=FAIL;PHASE=([A-Z0-9_]+);GATE=([A-Z0-9_]+)$'){
      'S4_V2_WORKER_FAILURE_PHASE='+$Matches[1]
      'S4_V2_WORKER_FAILURE_GATE='+$Matches[2]
      Fail 'WORKER_FAILED_NO_RETRY'
    }
    if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;HTTP=200;ENTITY_SETS=([0-9]+);EXCHANGE_PLANS=([0-9]+);SELECTCHANGES_DECLARED=(True|False);NOTIFYCHANGESRECEIVED_DECLARED=(True|False);ONEC_WRITES=0;BITRIX_CALLS=0$'){
      $when=[DateTime]::Parse($Matches[1]).ToUniversalTime()
      if($when -lt $started.AddSeconds(-2)){Fail 'STALE_V2_RECEIPT'}
      $entityCount=[int]$Matches[2]
      $planCount=[int]$Matches[3]
      $select=$Matches[4];$notify=$Matches[5]
      if($entityCount -lt 1 -or $entityCount -gt 10000 -or $planCount -gt 100 -or $readLines.Length -ne ($planCount+1)){Fail 'INVALID_METADATA_COUNTS'}
      for($j=1;$j -lt $readLines.Length;$j++){
        if($readLines[$j] -notmatch ('^PLAN_{0:D3}=[ -~]{1,1100}$' -f $j)){Fail 'INVALID_PLAN_LINE'}
      }
      $accepted=$true
      break
    }
  }
  if(-not $accepted){Fail 'RECEIPT_TIMEOUT_NO_RETRY'}
  $phase='WAIT_WORKER_FINISH'
  for($j=0;$j -lt 40;$j++){
    Start-Sleep -Milliseconds 500
    $task=$folder.GetTask($taskName)
    if([int]$task.State -ne 4){break}
  }
  if([int]$task.State -eq 4){Fail 'WORKER_STILL_RUNNING'}
  if([int]$task.LastTaskResult -ne 0){Fail 'WORKER_EXIT_NONZERO'}
  $phase='VERIFY_CUSTOMER_DB'
  if((Query $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'POST_SCAN_COUNT_CHANGED'}
  if((Query $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'POST_SCAN_DB_INTEGRITY_FAILED'}
  $phase='REMOVE_V2_TEMP_TASK'
  $folder.DeleteTask($taskName,0)
  'S4_V2_METADATA_HTTP=200'
  'S4_V2_ENTITY_SET_COUNT='+$entityCount
  'S4_V2_EXCHANGE_PLAN_SET_COUNT='+$planCount
  'S4_V2_SELECTCHANGES_DECLARED='+$select
  'S4_V2_NOTIFYCHANGESRECEIVED_DECLARED='+$notify
  for($j=1;$j -lt $readLines.Length;$j++){$readLines[$j]}
  'S4_V2_TEMP_TASK_DELETED=YES'
  'S4_V1_TASK_UNCHANGED=YES'
  'S4_MAIN_TASK_UNCHANGED=YES'
  'S4_6433_SNAPSHOT_UNCHANGED=YES'
  'S4_DELTA_READY=NOT_YET_PROVEN'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_ONEC_S4_V2_READONLY_SURVEY'
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^S4V2_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_ONEC_S4_V2_READONLY_SURVEY;GATE='+$gate+';PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

#requires -version 2
# SRV-only reconciliation of completed, committed 6433-row initial load.
# Verifies DB read-only, then removes ONLY its ready temporary task.
# Leaves original failing status as audit evidence, writes separate acceptance.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('S3_'+$Code)}
function Query([string]$Sqlite,[string]$Database,[string]$Statement){
  $result=@(& $Sqlite -readonly -batch -bail $Database $Statement 2>&1)
  if($LASTEXITCODE -ne 0){Fail 'READONLY_SQLITE_QUERY_FAILED'}
  return (($result -join '').Trim())
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $sql=Join-Path $root 'bin\sqlite3.exe'
  $db=Join-Path $root 'data\customers.db'
  $original=Join-Path $root 'state\customer-initial-load-status.txt'
  $accepted=Join-Path $root 'state\customer-initial-load-accepted.txt'
  $config=Join-Path $root 'config\collector.ini'
  $oldBridge='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
  foreach($f in @($sql,$db,$original,$config,$oldBridge)){
    if(-not [IO.File]::Exists($f)){Fail 'MACHINE_FILE_MISSING'}
    if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  }
  if([IO.File]::Exists($accepted)){Fail 'ACCEPTANCE_ALREADY_RECORDED'}
  foreach($dir in @($root,(Join-Path $root 'state'),(Join-Path $root 'data'))){
    if(-not [IO.Directory]::Exists($dir)){Fail 'DIRECTORY_MISSING'}
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DIRECTORY'}
  }
  foreach($pair in @(
    @($config,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),
    @($oldBridge,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0'))
  )){
    $raw=[IO.File]::ReadAllText([string]$pair[0],[Text.Encoding]::ASCII)
    foreach($flag in $pair[1]){
      if($raw -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_POLICY_CHANGED'}
    }
  }
  $originalStatus=[IO.File]::ReadAllText($original,[Text.Encoding]::ASCII).Trim()
  if($originalStatus -ne 'STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=BACKREAD'){Fail 'ORIGINAL_STATUS_NOT_EXPECTED'}
  $sched=New-Object -ComObject Schedule.Service
  $sched.Connect()
  $folder=$sched.GetFolder('\')
  $main=$folder.GetTask('MspCustomerStoreSync')
  if($null -eq $main){Fail 'MAIN_TASK_MISSING'}
  $mainAccount=$main.Definition.Principal.UserId
  if($mainAccount -eq 'S-1-5-19'){$mainSid=$mainAccount}else{$mainSid=(New-Object Security.Principal.NTAccount -ArgumentList $mainAccount).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($mainSid -ne 'S-1-5-19'){Fail 'MAIN_TASK_IDENTITY_CHANGED'}
  foreach($trigger in $main.Definition.Triggers){
    if($trigger.Enabled){Fail 'MAIN_AUTOSTART_ENABLED'}
  }
  $task=$folder.GetTask('MspCustomerStoreInitial6433')
  if($null -eq $task){Fail 'TEMP_TASK_MISSING'}
  $taskAccount=$task.Definition.Principal.UserId
  if($taskAccount -eq 'S-1-5-19'){$taskSid=$taskAccount}else{$taskSid=(New-Object Security.Principal.NTAccount -ArgumentList $taskAccount).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($taskSid -ne 'S-1-5-19'){Fail 'TEMP_TASK_IDENTITY_CHANGED'}
  if($task.State -ne 3){Fail 'TEMP_TASK_NOT_READY'}
  if($task.LastTaskResult -ne 1){Fail 'TEMP_TASK_RESULT_UNEXPECTED'}
  if($task.Definition.Triggers.Count -ne 0){Fail 'TEMP_TASK_HAS_TRIGGERS'}
  if($task.Definition.Actions.Count -ne 1){Fail 'TEMP_TASK_ACTION_COUNT'}
  $action=$task.Definition.Actions.Item(1)
  $expectedWorker=Join-Path $root 'bin\initial-load-customers-6433.ps1'
  $expectedExe=Join-Path $PSHOME 'powershell.exe'
  if($action.Type -ne 0 -or $action.Path -ine $expectedExe){Fail 'TEMP_TASK_EXECUTABLE_CHANGED'}
  if($action.Arguments -notlike ('*-File "'+$expectedWorker+'"*')){Fail 'TEMP_TASK_SCRIPT_CHANGED'}
  if($action.Arguments -match '(?i)[A-Z]:\\Users\\'){Fail 'TEMP_TASK_USER_PROFILE_DEPENDENCY'}
  $phase='SQLITE_READONLY_ACCEPTANCE'
  if((Query $sql $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) || ':' || sum(CASE WHEN buyer=1 AND deletion_mark=0 AND invalid=0 THEN 1 ELSE 0 END) FROM customers;") -ne '6433:6433:6433'){Fail 'DB_ROWS_GUID_ACTIVE_MISMATCH'}
  if((Query $sql $db "SELECT sum(CASE WHEN onec_type='LEGAL' THEN 1 ELSE 0 END) || ':' || sum(CASE WHEN onec_type='PERSON' THEN 1 ELSE 0 END) || ':' || sum(CASE WHEN onec_type='REVIEW' THEN 1 ELSE 0 END) FROM customers;") -ne '1941:4486:6'){Fail 'DB_TYPE_COUNTS_MISMATCH'}
  if((Query $sql $db "SELECT count(*) FROM scan_runs WHERE phase='INITIAL' AND status='COMPLETE' AND expected_count=6433 AND read_count=6433 AND unique_count=6433;") -ne '1'){Fail 'COMPLETED_SCAN_RUN_MISSING'}
  if((Query $sql $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_QUICK_CHECK_FAILED'}
  'PRE_CLEANUP_ROWS_UNIQUE_ACTIVE=6433:6433:6433'
  'PRE_CLEANUP_TYPES=1941:4486:6'
  'PRE_CLEANUP_INITIAL_RUNS=1'
  'PRE_CLEANUP_QUICK_CHECK=ok'
  $phase='DELETE_TEMPORARY_TASK_ONLY'
  $folder.DeleteTask('MspCustomerStoreInitial6433',0)
  $residue=$null
  try{$residue=$folder.GetTask('MspCustomerStoreInitial6433')}catch{}
  if($null -ne $residue){Fail 'TEMP_TASK_DELETE_UNCONFIRMED'}
  'TEMP_INITIAL_TASK_REMOVED=YES'
  $phase='POST_CLEANUP_CONFIRMATION'
  $mainAgain=$folder.GetTask('MspCustomerStoreSync')
  if($null -eq $mainAgain){Fail 'MAIN_TASK_DISAPPEARED'}
  foreach($trigger in $mainAgain.Definition.Triggers){
    if($trigger.Enabled){Fail 'MAIN_AUTOSTART_CHANGED'}
  }
  if((Query $sql $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'POST_CLEANUP_DB_CHANGED'}
  if((Query $sql $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'POST_CLEANUP_INTEGRITY_FAILED'}
  $phase='WRITE_SEPARATE_ACCEPTANCE_RECEIPT'
  $line='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+
    ';ACCEPTANCE=PASS;IDENTITY=LOCAL_SERVICE;ROWS=6433;UNIQUE_GUIDS=6433;ACTIVE=6433;LEGAL=1941;PERSON=4486;REVIEW=6;INITIAL_RUNS=1;DB_INTEGRITY=ok;TEMP_TASK_REMOVED=YES;AUTO_START=OFF;ONEC_WRITES=0;BITRIX_CALLS=0'
  $fs=New-Object IO.FileStream -ArgumentList @($accepted,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
    $bytes=[Text.Encoding]::ASCII.GetBytes($line)
    $fs.Write($bytes,0,$bytes.Length)
    $fs.Flush()
  }finally{$fs.Close()}
  if([IO.File]::ReadAllText($accepted,[Text.Encoding]::ASCII) -ne $line){Fail 'ACCEPTANCE_RECEIPT_VERIFY_FAILED'}
  'S3_FULL_INITIAL_IMPORT=PASS'
  'S3_ROWS=6433'
  'S3_UNIQUE_GUIDS=6433'
  'S3_LEGAL=1941'
  'S3_PERSON=4486'
  'S3_REVIEW=6'
  'S3_RECEIPT_WRITTEN=YES'
  'ORIGINAL_FAILURE_LOG_PRESERVED=YES'
  'MAIN_COLLECTOR_BOOT_AUTOSTART=OFF'
  'DATABASE_WRITES=NO'
  'OTHER_TASKS_CHANGED=NO'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_S3_RECONCILIATION'
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^S3_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_S3_RECONCILIATION;GATE='+$gate+';PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}

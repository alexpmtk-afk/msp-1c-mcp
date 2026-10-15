#requires -version 2
# Read-only diagnosis of LOCAL SERVICE SQLite schema failure on SRV.
# Query existing DB in READONLY mode, validate schema only in :memory:.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='HOST'
function Fail([string]$Reason){throw ('STORE_DIAG_'+$Reason)}
function Probe([string]$Label,[string]$Path){
  if(-not [IO.Directory]::Exists($Path)){($Label+'_DIRECTORY=MISSING');return}
  if(([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DIR'}
  $acl=[IO.Directory]::GetAccessControl($Path)
  $all=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
  $read=$false
  $write=$false
  foreach($entry in $all){
    if($entry.IdentityReference.Value -ne 'S-1-5-19'){continue}
    if($entry.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){continue}
    if(($entry.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadData) -ne 0){$read=$true}
    if(($entry.FileSystemRights -band [Security.AccessControl.FileSystemRights]::WriteData) -ne 0){$write=$true}
  }
  ($Label+'_LOCAL_SERVICE_READ_ACE='+$read)
  ($Label+'_LOCAL_SERVICE_WRITE_ACE='+$write)
}
function RunSqlite([string]$Label,[string]$Exe,[string]$Args,[string[]]$Queries){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$Exe
  $psi.Arguments=$Args
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardInput=$true
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $child=New-Object Diagnostics.Process
  $child.StartInfo=$psi
  try{
    if(-not $child.Start()){Fail 'SQLITE_CHILD_START_FAILED'}
    foreach($line in $Queries){$child.StandardInput.WriteLine($line)}
    $child.StandardInput.Close()
    $stdout=$child.StandardOutput.ReadToEnd()
    $stderr=$child.StandardError.ReadToEnd()
    $finished=$child.WaitForExit(10000)
    if(-not $finished){
      $child.Kill()
      ($Label+'_TIMEOUT=YES')
      return
    }
    ($Label+'_EXIT_CODE='+$child.ExitCode)
    $out=$stdout.Replace([char]13,' ').Replace([char]10,' ').Trim()
    $err=$stderr.Replace([char]13,' ').Replace([char]10,' ').Trim()
    if($out.Length -gt 200){$out=$out.Substring(0,200)}
    if($err.Length -gt 300){$err=$err.Substring(0,300)}
    ($Label+'_STDOUT='+$out)
    ($Label+'_STDERR='+$err)
  }catch{
    ($Label+'_EXCEPTION_TYPE='+$_.Exception.GetType().Name)
    $msg=$_.Exception.Message.Replace([char]13,' ').Replace([char]10,' ')
    if($msg.Length -gt 300){$msg=$msg.Substring(0,300)}
    ($Label+'_EXCEPTION_MESSAGE='+$msg)
  }finally{$child.Close()}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $bin=Join-Path $root 'bin'
  $exe=Join-Path $bin 'sqlite3.exe'
  $schema=Join-Path $root 'schema\customer-store.sql'
  $db=Join-Path $root 'data\customers.db'
  $state=Join-Path $root 'state\status.txt'
  $cfg=Join-Path $root 'config\collector.ini'
  'HOST='+$env:COMPUTERNAME
  'COLLECTOR_ROOT='+$root
  $phase='FILES_AND_ACL'
  foreach($n in @('ROOT','BIN','SCHEMA','DATA','STATE')){
    if($n -eq 'ROOT'){$path=$root}else{$path=Join-Path $root $n.ToLowerInvariant()}
    Probe ('ACL_'+$n) $path
  }
  foreach($file in @($exe,$schema,$cfg)){
    if(-not [IO.File]::Exists($file)){Fail 'EXPECTED_STAGE_FILE_MISSING'}
    if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  }
  'SQLITE_EXECUTABLE_PRESENT=YES'
  'SQL_SCHEMA_PRESENT=YES'
  'DB_EXISTS='+[IO.File]::Exists($db)
  if([IO.File]::Exists($db)){
    if(([IO.File]::GetAttributes($db) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DB'}
    'DB_BYTES='+([IO.FileInfo]$db).Length
  }
  'SERVICE_STATE_FILE_PRESENT='+[IO.File]::Exists($state)
  if([IO.File]::Exists($state)){
    $line=[IO.File]::ReadAllText($state,[Text.Encoding]::ASCII).Trim()
    if($line -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
      'SMOKE_STATE_GATE='+$Matches[1]
      'SMOKE_STATE_PHASE='+$Matches[2]
    }elseif($line -match '^UTC=[^;]+;STATUS=EMPTY_DB_PASS;IDENTITY=LOCAL_SERVICE;CUSTOMERS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){
      'SMOKE_STATE=EMPTY_DB_PASS'
    }else{'SMOKE_STATE=UNKNOWN_FORMAT'}
  }
  $phase='TASK'
  $s=New-Object -ComObject Schedule.Service
  $s.Connect()
  $task=$s.GetFolder('\').GetTask('MspCustomerStoreSync')
  if($null -eq $task){Fail 'TASK_NOT_FOUND'}
  $account=$task.Definition.Principal.UserId
  if($account -eq 'S-1-5-19'){$sid=$account}else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $account).Translate([Security.Principal.SecurityIdentifier]).Value}
  'TASK_RUN_AS_LOCAL_SERVICE='+($sid -eq 'S-1-5-19')
  'TASK_ENABLED='+$task.Enabled
  $boot=$false
  foreach($trigger in $task.Definition.Triggers){if($trigger.Type -eq 8 -and $trigger.Enabled){$boot=$true}}
  'TASK_BOOT_ENABLED='+$boot
  'TASK_LAST_RESULT='+$task.LastTaskResult
  $phase='SQLITE_MEMORY'
  $sqlList=@(
    ('.read "'+$schema+'"'),
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('customers','change_inbox','ingestion_checkpoint','scan_runs');"
  )
  RunSqlite 'SCHEMA_IN_MEMORY' $exe '-batch -bail :memory:' $sqlList
  $phase='DB_READONLY'
  if([IO.File]::Exists($db)){
    $args='-readonly "'+$db+'"'
    $q=@('PRAGMA quick_check;', "SELECT count(*) FROM sqlite_master WHERE type='table';")
    RunSqlite 'DB_READONLY' $exe $args $q
  }else{'DB_READONLY=SKIPPED_NO_FILE'}
  'DB_WRITES=NO'
  'FILES_CREATED=NO'
  'ACL_CHANGES=NO'
  'TASK_CHANGES=NO'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_SCHEMA_FAILURE_DIAG'
}catch{
  $reason='RUNTIME_ERROR'
  if($_.Exception.Message -match '^STORE_DIAG_([A-Z0-9_]+)$'){$reason=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_SCHEMA_FAILURE_DIAG;GATE='+$reason+';PHASE='+$phase
}

#requires -version 2
# Read-only machine-owned collection chain audit on physical SRV.
# No installer, scheduled-task edits, OData calls or files created.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='HOST'
function Fail([string]$Reason){throw ('AUDIT_'+$Reason)}
function Status([string]$Name,[string]$Path){
  if(-not [IO.Directory]::Exists($Path)){return ($Name+'=MISSING')}
  $attr=[IO.File]::GetAttributes($Path)
  if(($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0){return ($Name+'=REPARSE_BLOCK')}
  return ($Name+'=EXISTS')
}
function LocalServiceWriteHint([string]$Name,[string]$Path){
  if(-not [IO.Directory]::Exists($Path)){return ($Name+'_LOCAL_SERVICE_WRITE_ACE=NOT_PRESENT')}
  try{
    $acl=[IO.Directory]::GetAccessControl($Path)
    $rules=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
    $present=$false
    foreach($rule in $rules){
      if($rule.IdentityReference.Value -eq 'S-1-5-19' -and
         $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
         (($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::WriteData) -ne 0)){
        $present=$true
      }
    }
    if($present){return ($Name+'_LOCAL_SERVICE_WRITE_ACE=YES_NOT_EFFECTIVE_ACCESS_TEST')}
    return ($Name+'_LOCAL_SERVICE_WRITE_ACE=NO')
  }catch{return ($Name+'_LOCAL_SERVICE_WRITE_ACE=UNREADABLE')}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  if([IntPtr]::Size -ne 8){Fail 'X64_PROCESS_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $legacy='C:\ProgramData\MspBitrix24Bridge'
  $config=Join-Path $legacy 'config\bridge.ini'
  if(-not [IO.File]::Exists($config)){Fail 'EXISTING_BRIDGE_POLICY_MISSING'}
  $policy=[IO.File]::ReadAllText($config,[Text.Encoding]::ASCII)
  foreach($key in @('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')){
    if($policy -notmatch ('(?m)^'+[regex]::Escape($key)+'\s*$')){Fail 'EXISTING_BRIDGE_NOT_SAFE_IDLE'}
  }
  'HOST='+$env:COMPUTERNAME
  'COLLECTOR_ROOT='+$root
  'COLLECTOR_ACCOUNT_SID=S-1-5-19'
  'COLLECTOR_AUTOSTART_DESIGN=BOOT_TRIGGER'
  'EXISTING_BRIDGE_POLICY=SAFE_IDLE'
  $phase='EXISTING_TASK'
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $task=$folder.GetTask('MspBitrix24Bridge')
  if($null -eq $task){Fail 'EXISTING_BRIDGE_TASK_MISSING'}
  $definition=$task.Definition
  $runAs=$definition.Principal.UserId
  if($runAs -eq 'S-1-5-19'){$sid=$runAs}
  else {$sid=(New-Object Security.Principal.NTAccount -ArgumentList $runAs).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($sid -ne 'S-1-5-19'){Fail 'EXISTING_BRIDGE_NOT_LOCAL_SERVICE'}
  if($definition.Actions.Count -ne 1){Fail 'EXISTING_BRIDGE_ACTIONS_UNEXPECTED'}
  $action=$definition.Actions.Item(1)
  $expectedScript=Join-Path $legacy 'bin\bridge.ps1'
  if($action.Arguments -notlike ('*'+$expectedScript+'*')){Fail 'EXISTING_BRIDGE_ACTION_PATH_MISMATCH'}
  if(($action.Path+' '+$action.Arguments) -match '(?i)[A-Z]:\\Users\\'){Fail 'EXISTING_BRIDGE_USER_DEPENDENCY'}
  $hasBoot=$false
  foreach($trigger in $definition.Triggers){
    if($trigger.Type -eq 8 -and $trigger.Enabled){$hasBoot=$true}
  }
  'EXISTING_BRIDGE_RUN_AS_LOCAL_SERVICE=YES'
  'EXISTING_BRIDGE_BOOT_TRIGGER_ENABLED='+$hasBoot
  'EXISTING_BRIDGE_TASK_ENABLED='+$task.Enabled
  'EXISTING_BRIDGE_PROFILE_DEPENDENCY=NO'
  $collectorTask=$null
  try{$collectorTask=$folder.GetTask('MspCustomerStoreSync')}catch{}
  'COLLECTOR_TASK_EXISTS='+($null -ne $collectorTask)
  if($null -ne $collectorTask){Fail 'COLLECTOR_TASK_ALREADY_EXISTS_REVIEW_REQUIRED'}
  $phase='MACHINE_DIRECTORIES'
  foreach($name in @('ROOT','BIN','CONFIG','DATA','STATE','LOGS','STAGING','SECRETS','BACKUPS')){
    $sub=$name.ToLowerInvariant()
    if($name -eq 'ROOT'){$path=$root}else{$path=Join-Path $root $sub}
    $result=Status ('COLLECTOR_'+$name) $path
    $result
    if($result -like '*REPARSE_BLOCK'){Fail 'COLLECTOR_REPARSE_PATH'}
    LocalServiceWriteHint ('COLLECTOR_'+$name) $path
  }
  'COLLECTOR_SQLITE_EXE_PRESENT='+[IO.File]::Exists((Join-Path $root 'bin\sqlite3.exe'))
  'COLLECTOR_DB_PRESENT='+[IO.File]::Exists((Join-Path $root 'data\customers.db'))
  'COLLECTOR_CURL_PRESENT='+[IO.File]::Exists((Join-Path $root 'bin\curl.exe'))
  'COLLECTOR_CA_PRESENT='+[IO.File]::Exists((Join-Path $root 'config\curl-ca-bundle.crt'))
  'COLLECTOR_RUNNER_SCRIPT_PRESENT='+[IO.File]::Exists((Join-Path $root 'bin\collector.ps1'))
  'COLLECTOR_SECRETS_DIRECTORY_REQUIRED=YES'
  'COLLECTOR_QUEUE_PERSISTENCE_REQUIRED=YES'
  'COLLECTOR_BACKUP_MACHINE_OWNED_REQUIRED=YES'
  $who=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
  'INVOKING_SESSION_ADMIN='+$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  'PERMANENT_USER_PROFILE_DEPENDENCY_ALLOWED=NO'
  'SYSTEM_INSTALLER_NOT_EXECUTED=YES'
  'DATA_WRITES=NO'
  'FILES_CREATED=NO'
  'TASK_CHANGES=NO'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_MACHINE_OWNED_CHAIN_AUDIT'
}catch{
  $reason='RUNTIME_ERROR'
  if($_.Exception.Message -match '^AUDIT_([A-Z0-9_]+)$'){$reason=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_MACHINE_OWNED_CHAIN_AUDIT;GATE='+$reason
  'FAILURE_PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
}

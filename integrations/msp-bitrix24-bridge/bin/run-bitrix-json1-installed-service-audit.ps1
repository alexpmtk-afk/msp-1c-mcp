#requires -version 2
# One-shot zero-trigger LocalService audit for installed inactive JSON1 worker.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('AUDIT_'+$Code)}
function Hash([string]$File){
 $s=New-Object System.Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$s.Clear()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $id
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $probe=Join-Path $root 'bin\probe-bitrix-json1-installed-service.ps1'
 $status=Join-Path $root 'state\bitrix-json1-installed-runtime-status.txt'
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $backup=Join-Path $root 'staging\bitrix-search-outbound-before-json1.ps1'
 $upgrade=Join-Path $root 'state\bitrix-worker-json1-stage-accepted.txt'
 $db=Join-Path $root 'data\customers.db'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 foreach($file in @($curl,$ca,$worker,$backup,$upgrade,$db,$sqlite)){
  if(-not [IO.File]::Exists($file)){Fail 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 if([IO.File]::Exists($probe) -or [IO.File]::Exists($status)){Fail 'PREVIOUS_AUDIT_REQUIRES_DIAGNOSIS'}
 if([IO.File]::Exists((Join-Path $root 'config\bitrix-search-worker.ini')) -or [IO.File]::Exists((Join-Path $root 'secrets\bitrix-search-worker.dpapi'))){Fail 'WORKER_CONFIG_PRESENT'}
 if((Hash $worker) -ne '53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4'){Fail 'WORKER_CHANGED'}
 if((Hash $backup) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'BACKUP_CHANGED'}
 $mark=[IO.File]::ReadAllText($upgrade,[Text.Encoding]::ASCII).Trim()
 if($mark -notmatch ';STATUS=PASS;STAGE=BITRIX_JSON1_WORKER_INACTIVE_UPGRADE;OLD_HASH=8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff;NEW_HASH=53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4;CUSTOMERS=6433;INDEX=6433;NETWORK_WORKER_ENABLED=NO$'){Fail 'UPGRADE_NOT_ACCEPTED'}
 $scheduler=New-Object -ComObject Schedule.Service
 $scheduler.Connect()
 $folder=$scheduler.GetFolder('\')
 $main=$folder.GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'MAIN_COLLECTOR_MISSING'}
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_COLLECTOR_ENABLED'}}
 foreach($t in $folder.GetTasks(1)){
  foreach($act in $t.Definition.Actions){
   if($act.Type -eq 0 -and $act.Arguments -match 'bitrix-search-outbound-once\.ps1'){Fail 'WORKER_SCHEDULED_ALREADY'}
  }
 }
 $taskName='MspCustomerStoreBitrixInstalledJson1Audit'
 $existing=$null
 try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){Fail 'AUDIT_TASK_ALREADY_EXISTS'}
 $phase='DOWNLOAD_PINNED_PROBE'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/1e4f90e67f9e812f2fe63384baab1806f46a36c4/integrations/msp-bitrix24-bridge/bin/probe-bitrix-json1-installed-service.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $probe $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($probe)){Fail 'PROBE_DOWNLOAD_FAILED'}
 if((Hash $probe) -ne 'HASH_OF_SERVICE_PROBE_TO_FILL'){Fail 'PROBE_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($probe,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'PROBE_PS2_PARSE'}
 'INSTALLED_AUDIT_PROBE_SHA256=PASS'
 $phase='LOCAL_SERVICE_AUDIT'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$scheduler.NewTask(0)
 $definition.RegistrationInfo.Description='One-time read-only LocalService installed Bitrix JSON1 worker audit'
 $definition.Principal.UserId=$service
 $definition.Principal.LogonType=5
 $definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true
 $definition.Settings.ExecutionTimeLimit='PT3M'
 $definition.Settings.MultipleInstances=2
 $action=$definition.Actions.Create(0)
 $action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$definition,2,$service,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($task.Definition.Triggers.Count -ne 0){Fail 'TASK_HAS_TRIGGERS'}
 $start=[DateTime]::UtcNow
 $null=$task.Run($null)
 $passed=$false
 for($i=0;$i -lt 240;$i++){
  Start-Sleep -Milliseconds 500
  if(-not [IO.File]::Exists($status)){continue}
  $line=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII).Trim()
  if($line -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
   'INSTALLED_AUDIT_FAILURE_GATE='+$Matches[1]
   'INSTALLED_AUDIT_FAILURE_PHASE='+$Matches[2]
   Fail 'LOCAL_SERVICE_AUDIT_FAILED'
  }
  if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;INSTALLED_WORKER_SHA256=PASS;ROLLBACK_SHA256=PASS;ADAPTER_SHA256=PASS;PS2_PARSE=PASS;JSON1_CONTRACT=PASS;CUSTOMERS=6433;INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){
   if([DateTime]::Parse($Matches[1]).ToUniversalTime() -ge $start.AddSeconds(-2)){$passed=$true;break}
  }
 }
 if(-not $passed){Fail 'RESULT_MISSING_OR_INVALID'}
 $phase='CLEANUP'
 if((Hash $worker) -ne '53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4'){Fail 'WORKER_MODIFIED'}
 if((Hash $backup) -ne '8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff'){Fail 'BACKUP_MODIFIED'}
 $folder.DeleteTask($taskName,0)
 $left=$null
 try{$left=$folder.GetTask($taskName)}catch{}
 if($null -ne $left){Fail 'TEMP_TASK_REMOVAL_UNCONFIRMED'}
 'INSTALLED_JSON1_WORKER_LOCAL_SERVICE=PASS'
 'WORKER_AND_BACKUP_HASHES=PASS'
 'PS2_PARSE=PASS'
 'CUSTOMERS_AND_INDEX_UNCHANGED=6433'
 'INSTALLED_AUDIT_TASK_REMOVED=YES'
 'WORKER_STILL_DISABLED=YES'
 'CUSTOMER_DATA_EXPORTED=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_JSON1_INSTALLED_LOCAL_SERVICE_ACCEPTANCE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^AUDIT_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_JSON1_INSTALLED_LOCAL_SERVICE_ACCEPTANCE;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}
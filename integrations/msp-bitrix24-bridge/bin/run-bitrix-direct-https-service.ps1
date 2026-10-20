#requires -version 2
# One-shot zero-trigger LocalService SRV -> Bitrix24 HTTPS/TLS connectivity test.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('RUN_DIRECT_HTTPS_'+$Code)}
function Hash([string]$Path){
 $s=New-Object Security.Cryptography.SHA256Managed
 try{return [BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-','').ToLowerInvariant()}
 finally{$s.Clear()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $wid=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $wid
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $probe=Join-Path $root 'bin\probe-bitrix-direct-https-service.ps1'
 $status=Join-Path $root 'state\bitrix-direct-https-smoke-status.txt'
 $db=Join-Path $root 'data\customers.db'
 $accept=Join-Path $root 'state\bitrix-json1-installed-runtime-status.txt'
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $taskName='MspBitrixDirectHttpsProbe'
 foreach($f in @($curl,$ca,$db,$accept,$worker)){
  if(-not [IO.File]::Exists($f)){Fail 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 if([IO.File]::Exists($probe) -or [IO.File]::Exists($status)){Fail 'PREVIOUS_PROBE_REQUIRES_DIAGNOSIS'}
 foreach($f in @((Join-Path $root 'config\bitrix-search-worker.ini'),(Join-Path $root 'secrets\bitrix-search-worker.dpapi'))){
  if([IO.File]::Exists($f)){Fail 'OLD_WORKER_CONFIG_PRESENT'}
 }
 if((Hash $worker) -ne '53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4'){Fail 'WORKER_CHANGED'}
 $ar=[IO.File]::ReadAllText($accept,[Text.Encoding]::ASCII).Trim()
 if($ar -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;INSTALLED_WORKER_SHA256=PASS;ROLLBACK_SHA256=PASS;ADAPTER_SHA256=PASS;PS2_PARSE=PASS;JSON1_CONTRACT=PASS;CUSTOMERS=6433;INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INSTALLED_AUDIT_NOT_ACCEPTED'}
 $scheduler=New-Object -ComObject Schedule.Service
 $scheduler.Connect()
 $folder=$scheduler.GetFolder('\')
 $main=$folder.GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'MAIN_COLLECTOR_MISSING'}
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_COLLECTOR_AUTOSTART_ENABLED'}}
 foreach($task in $folder.GetTasks(1)){
  foreach($action in $task.Definition.Actions){
   if($action.Type -eq 0 -and $action.Arguments -match 'bitrix-search-outbound-once\.ps1'){Fail 'OLD_WORKER_SCHEDULED'}
  }
 }
 $existing=$null
 try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){Fail 'TASK_ALREADY_EXISTS'}
 $phase='DOWNLOAD_PINNED_PROBE'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/8801e4537e039b30e62fee945774afa53e3327f5/integrations/msp-bitrix24-bridge/bin/probe-bitrix-direct-https-service.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --proto '=https' --tlsv1.2 --tls-max 1.2 --cacert $ca --max-redirs 0 --output $probe $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($probe)){Fail 'DOWNLOAD_FAILED'}
 if((Hash $probe) -ne 'cb738351c2ea6066e59a8e567264d38d297283dfbe734e93bf70affd9ccc5533'){Fail 'PROBE_SHA256_MISMATCH'}
 $parse=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($probe,[Text.Encoding]::ASCII),[ref]$parse)
 if($parse -and $parse.Count -gt 0){Fail 'PS2_PARSE_FAILED'}
 'DIRECT_HTTPS_PROBE_SHA256=PASS'
 $phase='LOCAL_SERVICE_HTTPS_PROBE'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$scheduler.NewTask(0)
 $definition.RegistrationInfo.Description='One-time no-REST LocalService direct Bitrix HTTPS/TLS probe'
 $definition.Principal.UserId=$service
 $definition.Principal.LogonType=5
 $definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true
 $definition.Settings.ExecutionTimeLimit='PT2M'
 $definition.Settings.MultipleInstances=2
 $act=$definition.Actions.Create(0)
 $act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$definition,2,$service,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($task.Definition.Triggers.Count -ne 0){Fail 'UNEXPECTED_AUTOMATIC_TRIGGER'}
 $started=[DateTime]::UtcNow
 $null=$task.Run($null)
 $ok=$false
 $code=0
 for($i=0;$i -lt 180;$i++){
  Start-Sleep -Milliseconds 500
  if(-not [IO.File]::Exists($status)){continue}
  $line=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII).Trim()
  if($line -match '^STATUS=FAIL;GATE=([A-Z0-9_]+);PHASE=([A-Z0-9_]+)$'){
   'DIRECT_HTTPS_FAILURE_GATE='+$Matches[1]
   'DIRECT_HTTPS_FAILURE_PHASE='+$Matches[2]
   Fail 'LOCAL_SERVICE_PROBE_FAILED'
  }
  if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;TARGET=b24-uwmjda.bitrix24.ru;TLS_VERIFY=PASS;HTTP_STATUS=([0-9]{3});CUSTOMERS=6433;INDEX=6433;WORKER_ENABLED=NO;REST_CALLS=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0$'){
   if([DateTime]::Parse($Matches[1]).ToUniversalTime() -ge $started.AddSeconds(-2)){$code=[int]$Matches[2];$ok=$true;break}
  }
 }
 if(-not $ok){Fail 'RESULT_MISSING_OR_INVALID'}
 $phase='CLEANUP'
 if((Hash $worker) -ne '53007f8a1e3a6a193826876a965ec321f52183d266bf0a8d9842057f30d603d4'){Fail 'WORKER_MODIFIED'}
 $folder.DeleteTask($taskName,0)
 $left=$null
 try{$left=$folder.GetTask($taskName)}catch{}
 if($null -ne $left){Fail 'TEMP_TASK_REMOVAL_UNCONFIRMED'}
 'DIRECT_BITRIX_HTTPS_LOCAL_SERVICE=PASS'
 'DIRECT_BITRIX_TLS_CERTIFICATE=PASS'
 'DIRECT_BITRIX_HTTP_STATUS='+$code
 'DIRECT_HTTPS_TEMP_TASK_REMOVED=YES'
 'MAIN_COLLECTOR_AUTOSTART=OFF'
 'WORKER_STILL_DISABLED=YES'
 'CUSTOMER_DATA_EXPORTED=NO'
 'BITRIX_REST_CALLS=NO'
 'ONEC_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_DIRECT_HTTPS_LOCAL_SERVICE_ACCEPTANCE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^RUN_DIRECT_HTTPS_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_DIRECT_HTTPS_LOCAL_SERVICE_ACCEPTANCE;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}
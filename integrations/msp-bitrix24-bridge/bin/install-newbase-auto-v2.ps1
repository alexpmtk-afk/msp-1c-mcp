#requires -version 2
# One-time unattended installation of TEST-NewBase 08:30 + 1-minute Bitrix24 sync.
# Registers DISABLED automation first, performs a LocalService acceptance run, then activates.
param([string]$ExpectedComputerName='SRV',[string]$SourceCommit)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$phase='PRECHECK'
$taskName='MspNewbaseAutoV2';$marker=Join-Path $root 'state\msp-newbase-auto-tick-v2.status'
function Fail([string]$Why){throw ('INSTALL_'+$Why)}
function Digest([string]$Path){
 $sha=New-Object Security.Cryptography.SHA256Managed
 try{return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-','').ToLowerInvariant()}
 finally{$sha.Clear()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $who=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $who.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
 if($SourceCommit -notmatch '^[a-f0-9]{40}$'){Fail 'PINNED_COMMIT_REQUIRED'}
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 foreach($f in @($curl,$ca,(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'data\customers.db'),(Join-Path $root 'secrets\onec-test-odata.dpapi'),(Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'))){
  if(-not [IO.File]::Exists($f)){Fail 'MACHINE_PREREQUISITES_MISSING'}
 }
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect()
 $folder=$sched.GetFolder('\')
 $previous=$null
 try{$previous=$folder.GetTask($taskName)}catch{}
 if($null -ne $previous){Fail 'AUTOMATION_TASK_ALREADY_EXISTS'}
 if([IO.File]::Exists($marker)){Fail 'OLD_TICK_STATUS_DIAGNOSE_FIRST'}
 $phase='STAGE_PINNED_SCRIPTS'
 $files=@('refresh-newbase-source-v2.ps1','msp-newbase-bitrix-core-v2.ps1','count-newbase-active-v2.ps1','pump-newbase-bitrix-batch-v2.ps1','msp-newbase-auto-tick-v2.ps1')
 $where=Join-Path $root 'staging\newbase-auto-v2'
 if([IO.Directory]::Exists($where)){Fail 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($where)
 $raw='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/'+$SourceCommit+'/integrations/msp-bitrix24-bridge/bin/'
 $parserErrors=$null
 foreach($filename in $files){
  $staged=Join-Path $where $filename
  & $curl -q --fail --silent --show-error --noproxy '*' --proto '=https' --tlsv1.2 --tls-max 1.2 --cacert $ca --max-redirs 0 --connect-timeout 10 --max-time 50 --output $staged ($raw+$filename)
  if($LASTEXITCODE -ne 0){Fail 'SOURCE_DOWNLOAD_FAILED'}
  if(([IO.File]::ReadAllBytes($staged)).Length -lt 1000){Fail 'SCRIPT_TOO_SMALL'}
  $pErrors=$null
  $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($staged,[Text.Encoding]::UTF8),[ref]$pErrors)
  if($null -ne $pErrors -and $pErrors.Count -gt 0){Fail 'PS2_PARSE_FAILED'}
  if((Digest $staged).Length -ne 64){Fail 'SHA256_INVALID'}
  $to=Join-Path $root ('bin\'+$filename)
  if([IO.File]::Exists($to)){Fail 'WORKER_ALREADY_INSTALLED_DIAGNOSE_FIRST'}
  [IO.File]::Copy($staged,$to,$false)
  if((Digest $to) -ne (Digest $staged)){Fail 'LOCAL_COPY_HASH_MISMATCH'}
 }
 $phase='REGISTER_TASK_PAUSED'
 $id=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sched.NewTask(0)
 $def.RegistrationInfo.Description='TEST NewBase buyers to local SQLite and direct Bitrix24; 08:30 snapshot + 1-minute monitor'
 $def.Principal.UserId=$id;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.StartWhenAvailable=$true
 $def.Settings.ExecutionTimeLimit='PT20M';$def.Settings.MultipleInstances=2
 $trigger=$def.Triggers.Create(2)
 $trigger.DaysInterval=1
 $trigger.StartBoundary=[DateTime]::Now.AddMinutes(2).ToString('yyyy-MM-ddTHH:mm:ss')
 $trigger.Repetition.Interval='PT1M'
 $trigger.Repetition.Duration='P1D'
 $trigger.Enabled=$false
 $act=$def.Actions.Create(0)
 $act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $root 'bin\msp-newbase-auto-tick-v2.ps1')+'" -ExpectedComputerName SRV -MaxBatchesPerTick 10'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$id,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($task.Definition.Triggers.Count -ne 1 -or $task.Definition.Triggers.Item(1).Enabled){Fail 'TASK_NOT_PAUSED'}
 $phase='FIRST_LOCAL_SERVICE_RUN'
 $null=$task.Run($null)
 $deadline=[DateTime]::UtcNow.AddMinutes(19)
 $accepted=$false
 while([DateTime]::UtcNow -lt $deadline){
  Start-Sleep -Seconds 4
  if(-not [IO.File]::Exists($marker)){continue}
  $text=[IO.File]::ReadAllText($marker,[Text.Encoding]::ASCII).Trim()
  if($text -match '^UTC=[^;]+;STATUS=PASS;SOURCE_SCAN=YES;REASON=INITIAL;BATCH_SOURCE=[0-9]+;CREATED=[0-9]+$'){$accepted=$true;break}
  if($text -match '^STATUS=FAIL;GATE='){Fail 'FIRST_RUN_FAILED_CHECK_STATUS_FILE'}
 }
 if(-not $accepted){Fail 'FIRST_RUN_TIMEOUT_OR_UNCONFIRMED'}
 $phase='ENABLE_AUTOMATIC_MINUTE_TRIGGER'
 $current=$folder.GetTask($taskName)
 $ready=$current.Definition
 $ready.Triggers.Item(1).Enabled=$true
 $null=$folder.RegisterTaskDefinition($taskName,$ready,2,$id,$null,5,$null)
 $final=$folder.GetTask($taskName)
 if(-not $final.Enabled -or -not $final.Definition.Triggers.Item(1).Enabled){Fail 'TRIGGER_NOT_ENABLED'}
 'SOURCE_DATABASE=TEST_NEWBASE'
 'FIRST_AUTOMATED_CYCLE=PASS'
 'LOCAL_SERVICE=YES'
 'SCHEDULE=EVERY_MINUTE'
 'FULL_SNAPSHOT_TIME=08:30_SERVER_LOCAL'
 'BITRIX_TRANSPORT=BATCH'
 'AUTO_START=ENABLED'
 'PRODUCTION_1C=UNTOUCHED'
 'RESULT=PASS;STAGE=MSP_NEWBASE_AUTOMATION_INSTALL_V2'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^INSTALL_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_NEWBASE_AUTOMATION_INSTALL_V2;GATE='+$gate+';PHASE='+$phase
 'AUTOMATION_MUST_STAY_DISABLED=YES'
 exit 1
}
#requires -version 2
# Guarded no-trigger SRV installer/launcher for ONE bounded 525-contact Bitrix name repair.
# Requires last 20-card PASS, pristine 546:21:525:0:0 queue. No automatic recurrence.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function Gate([string]$Code){throw ('NAME_DRAIN_'+$Code)}
function Hash([string]$Path){$h=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){Gate 'HOST_DENIED'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Gate 'PS2_X64_ONLY'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Gate 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $prior=Join-Path $root 'state\msp-bitrix-unnamed-fix-batch20-v1.status'
 $status=Join-Path $root 'state\msp-bitrix-unnamed-name-drain-v1.status'
 $journal=Join-Path $root 'state\msp-bitrix-unnamed-name-drain-v1.journal'
 $backup=Join-Path $root 'data\customers.before-unnamed-name-drain-v1.sqlite.bak'
 if([IO.File]::Exists($status) -or [IO.File]::Exists($journal) -or [IO.File]::Exists($backup)){Gate 'PREVIOUS_ATTEMPT_PRESENT'}
 foreach($rel in @('data\customers.db','state\msp-bitrix-unnamed-fix-batch20-v1.status','bin\sqlite3.exe','bin\curl.exe','config\curl-ca-bundle.crt','bin\msp-newbase-bitrix-core-v2.ps1','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi')){
  $f=Join-Path $root $rel
  if(-not [IO.File]::Exists($f)){Gate 'REQUIRED_INPUT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Gate 'REPARSE_DENIED'}
 }
 if((Hash (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')) -ne '6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852'){Gate 'BITRIX_CORE_HASH_CHANGED'}
 $receipt=[IO.File]::ReadAllText($prior,[Text.Encoding]::ASCII).Trim()
 if($receipt -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;MODE=Batch;POST_BATCHES=1;VERIFIED=20;CRM_WRITES=20;DONE=21;PENDING=525;UNCERTAIN=0;INTENT=0;BACKREAD=PASS;PHONE_EMAIL_PRESERVED=PASS;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0$'){Gate 'BATCH20_NOT_ACCEPTED'}
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $counts=& $exe -readonly -batch -bail $db "SELECT count(*)||':'||coalesce(sum(state='DONE'),0)||':'||coalesce(sum(state='PENDING'),0)||':'||coalesce(sum(state='INTENT'),0)||':'||coalesce(sum(state='UNCERTAIN'),0) FROM msp_bitrix_name_fix;"
 if($LASTEXITCODE -ne 0 -or [string]$counts -ne '546:21:525:0:0'){Gate 'QUEUE_CHANGED'}
 $integrity=& $exe -readonly -batch -bail $db 'PRAGMA quick_check;'
 if($LASTEXITCODE -ne 0 -or [string]$integrity -ne 'ok'){Gate 'SQLITE_INTEGRITY'}
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect();$folder=$sched.GetFolder('\')
 $last=$folder.GetTask('MspBitrixNameFixBatch20V1')
 if($null -eq $last -or [int]$last.State -ne 3 -or [int]$last.LastTaskResult -ne 0){Gate 'BATCH20_TASK_UNCONFIRMED'}
 $name='MspBitrixNameFixDrainV1'
 $existing=$null;try{$existing=$folder.GetTask($name)}catch{}
 if($null -ne $existing){Gate 'TASK_ALREADY_EXISTS'}
 foreach($t in @($folder.GetTasks(0))){
  if($t.Name -match '^Msp(CustomerStore|Newbase|NewBase|BitrixPhone|BitrixUnnamed|BitrixName)' -and [int]$t.State -eq 4){Gate 'ANOTHER_RELATED_TASK_RUNNING'}
 }
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\bitrix-name-drain-v1'
 if([IO.Directory]::Exists($dir)){Gate 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'drain-bitrix-unnamed-name-queue-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/e124460d2fb2d171f06b9e44bc8c6d4d407dde4a/integrations/msp-bitrix24-bridge/bin/drain-bitrix-unnamed-name-queue-v1.ps1'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Gate 'DOWNLOAD_FAILED'}
 if((Hash $worker) -ne '1f63649052fef64427f8f41576fec31779cd7a34b0369ef8a53ea91c7f368349'){Gate 'WORKER_HASH_MISMATCH'}
 $parseErrors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$parseErrors)
 if($parseErrors -and $parseErrors.Count -gt 0){Gate 'WORKER_PS2_PARSE_FAILED'}
 'NAME_DRAIN_WORKER_HASH=PASS'
 'PREVIOUS_21_NAMES=PASS'
 'REMAINING_NAMES=525'
 $phase='REGISTER'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sched.NewTask(0)
 $def.RegistrationInfo.Description='One-time guarded 525 existing Bitrix contact name replacements, up to 27 independently readback-verified batches. No auto sync.'
 $def.Principal.UserId=$account;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT4H';$def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0);$action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV -BatchSize 20 -MaxBatches 27'
 $null=$folder.RegisterTaskDefinition($name,$def,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){Gate 'SCHEDULE_NOT_EMPTY'}
 $phase='START'
 $null=$task.Run($null)
 'NAME_DRAIN_TASK=STARTED'
 'NAME_DRAIN_STATUS_FILE='+$status
 'NAME_DRAIN_JOURNAL_FILE='+$journal
 'MAX_NEW_CRM_WRITES=525';'ONEC_WRITES=0';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=MSP_BITRIX_UNNAMED_NAME_DRAIN_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NAME_DRAIN_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_BITRIX_UNNAMED_NAME_DRAIN_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

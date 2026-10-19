#requires -version 2
# One-card live CRM phone pilot. Must only run after queue acceptance and explicit admin invocation.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function StopSafe([string]$Code){throw ('PHONE_PILOT_'+$Code)}
function Sha256([string]$File){$h=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}}
try{
 if($ExpectedComputerName -ne 'SRV' -or $env:COMPUTERNAME -ne 'SRV'){StopSafe 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){StopSafe 'PS2_X64_ONLY'}
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){StopSafe 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $receipt=Join-Path $root 'state\msp-bitrix-phone-queue-v1.status'
 $pilotReceipt=Join-Path $root 'state\msp-bitrix-phone-sync-pilot-v1.status'
 foreach($rel in @('data\customers.db','state\msp-bitrix-phone-queue-v1.status','bin\curl.exe','bin\sqlite3.exe','config\curl-ca-bundle.crt','bin\msp-newbase-bitrix-core-v2.ps1','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi')){
  $f=Join-Path $root $rel
  if(-not [IO.File]::Exists($f) -or (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){StopSafe 'COMPONENT_MISSING'}
 }
 if([IO.File]::Exists($pilotReceipt)){StopSafe 'PILOT_ALREADY_ATTEMPTED'}
 if((Sha256 (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')) -ne '6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852'){StopSafe 'CORE_HASH_MISMATCH'}
 $body=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII)
 if($body -notmatch 'STATUS=PASS;SOURCE=TEST_NEWBASE;QUEUE_BUYERS=4031;QUEUE_PHONE_ROWS=4032;COMPANY_SINGLE=1089;CONTACT_SINGLE=2941;TWO_PHONE_BUYERS=1;REVIEW_EXCLUDED=36;BACKUP=VERIFIED;SQLITE_QUICK_CHECK=OK;CRM_WRITES=0'){StopSafe 'QUEUE_NOT_ACCEPTED'}
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect();$folder=$sched.GetFolder('\')
 $prior=$folder.GetTask('MspBitrixPhoneQueueV1')
 if($null -eq $prior -or [int]$prior.State -ne 3 -or [int]$prior.LastTaskResult -ne 0){StopSafe 'QUEUE_TASK_NOT_PASS'}
 $name='MspBitrixPhonePilotV1'
 $existing=$null;try{$existing=$folder.GetTask($name)}catch{}
 if($null -ne $existing){StopSafe 'TASK_ALREADY_EXISTS'}
 foreach($t in @($folder.GetTasks(0))){
  if($t.Name -match '^Msp(CustomerStore|Newbase|NewBase|BitrixPhone)' -and [int]$t.State -eq 4){StopSafe 'TASK_CONCURRENT'}
 }
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\bitrix-phone-pilot-v1'
 if([IO.Directory]::Exists($dir)){StopSafe 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'msp-bitrix-phone-sync-worker-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/8f9e8e355410f6e8d9ee70ba254f489d577b9182/integrations/msp-bitrix24-bridge/bin/msp-bitrix-phone-sync-worker-v1.ps1'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){StopSafe 'DOWNLOAD_FAILED'}
 if((Sha256 $worker) -ne 'cbc07e9fc2f7ab3be63a6ae637fb1bfbad5f8efeb028e0ad9b500e66bc408a8c'){StopSafe 'WORKER_HASH_MISMATCH'}
 $e=$null;$null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$e)
 if($e -and $e.Count -gt 0){StopSafe 'PS2_PARSE_FAILED'}
 'BITRIX_PHONE_PILOT_WORKER_VERIFIED=PASS'
 $phase='REGISTER'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sched.NewTask(0)
 $def.RegistrationInfo.Description='One-time real Bitrix24 single mapped company phone addition and readback; no 1C writes'
 $def.Principal.UserId=$account;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT30M';$def.Settings.MultipleInstances=2
 $act=$def.Actions.Create(0);$act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV -Mode Pilot -MaxCards 1'
 $null=$folder.RegisterTaskDefinition($name,$def,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){StopSafe 'TRIGGERS_PRESENT'}
 $phase='START';$null=$task.Run($null)
 'BITRIX_PHONE_PILOT_TASK=STARTED';'PILOT_STATUS_FILE='+$pilotReceipt
 'ONEC_WRITES=0';'CRM_WRITES_MAX=1';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=MSP_BITRIX_PHONE_PILOT_V1'
}catch{
 $gate='RUNTIME'
 if($_.Exception.Message -match '^PHONE_PILOT_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_BITRIX_PHONE_PILOT_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

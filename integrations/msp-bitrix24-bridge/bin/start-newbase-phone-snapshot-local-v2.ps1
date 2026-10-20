#requires -version 2
# One-shot LOCAL SERVICE launch: TEST NewBase contact phones -> local isolated SQLite.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='HOST'
function StopSafe([string]$Code){throw ('PHONE_STAGE_'+$Code)}
function Sha256([string]$File){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){StopSafe 'HOST_NOT_SRV'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){StopSafe 'PS2_X64_REQUIRED'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){StopSafe 'ADMIN_REQUIRED'}
 $base='C:\ProgramData\MspCustomerStore'
 $receipt=Join-Path $base 'state\customer-phone-coverage-readonly-v2.txt'
 $done=Join-Path $base 'state\customer-phone-snapshot-v2.status'
 $dest=Join-Path $base 'data\phone-source-newbase-v1.sqlite'
 $pending=Join-Path $base 'data\phone-source-newbase-v1.sqlite.pending'
 $curl=Join-Path $base 'bin\curl.exe'
 $ca=Join-Path $base 'config\curl-ca-bundle.crt'
 foreach($file in @($receipt,$curl,$ca)){
  if(-not [IO.File]::Exists($file)){StopSafe 'SOURCE_FILE_MISSING'}
  if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){StopSafe 'REPARSE_DENIED'}
 }
 if([IO.File]::Exists($done) -or [IO.File]::Exists($dest) -or [IO.File]::Exists($pending)){StopSafe 'SNAPSHOT_ALREADY_EXISTS'}
 $content=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 if($content -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;ACTIVE_BUYERS=6433;CONTACT_ROWS=10751;MATCHED_BUYER_ROWS=9975;OTHER_ROWS=776;PHONE_NUMBER_ROWS=4068;PHONE_WITHOUT_CODES_ROWS=3468;DISPLAY_ROWS=9973;PHONE_TYPE_ROWS=4068;PHONE_CANDIDATE_ROWS=4068;BUYERS_WITH_PHONE=4067;BUYERS_MULTIPLE_PHONES=1;PAGES=108;ONEC_WRITES=0;CRM_WRITES=0;DB_WRITES=0;PII_EXPORTED=0$'){StopSafe 'COVERAGE_NOT_ACCEPTED'}
 $phase='SCHEDULER'
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect()
 $folder=$sched.GetFolder('\')
 $prior=$folder.GetTask('MspNewbasePhoneCoverageReadOnlyV2')
 if($null -eq $prior -or [int]$prior.State -ne 3 -or [int]$prior.LastTaskResult -ne 0){StopSafe 'PRIOR_TASK_NOT_PASS'}
 $previousReceipt=Join-Path $base 'state\customer-phone-snapshot-v1.status'
 if(-not [IO.File]::Exists($previousReceipt)){StopSafe 'V1_FAILURE_RECEIPT_MISSING'}
 $previousStatus=[IO.File]::ReadAllText($previousReceipt,[Text.Encoding]::ASCII).Trim()
 if($previousStatus -ne 'STATUS=FAIL;SOURCE=TEST_NEWBASE;PHASE=CONTACT_COUNT_BEFORE;GATE=NETWORK;PII_EXPORTED=0'){StopSafe 'V1_FAILURE_RECEIPT_CHANGED'}
 $previousTask=$folder.GetTask('MspNewbasePhoneSnapshotLocalV1')
 if($null -eq $previousTask -or [int]$previousTask.State -ne 3 -or [int]$previousTask.LastTaskResult -ne 1 -or $previousTask.Definition.Triggers.Count -ne 0){StopSafe 'V1_TASK_NOT_FAILED_IDLE'}
 'PHONE_SNAPSHOT_V2_RETRY_GATE=PASS'
 $name='MspNewbasePhoneSnapshotLocalV2'
 $registered=$null
 try{$registered=$folder.GetTask($name)}catch{}
 if($null -ne $registered){StopSafe 'TASK_ALREADY_EXISTS'}
 $phase='DOWNLOAD'
 $dir=Join-Path $base 'staging\phone-snapshot-v2'
 if([IO.Directory]::Exists($dir)){StopSafe 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'snapshot-newbase-phone-source-local-v2.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/ccc47387a108225c15f5c3c8940c9d5fddc88523/integrations/msp-bitrix24-bridge/bin/snapshot-newbase-phone-source-local-v2.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){StopSafe 'DOWNLOAD_FAILED'}
 if((Sha256 $worker) -ne '68193c03f2c7f0dff11e11908b8443fdc7cfc6b1b35839b5291fec9d891453dc'){StopSafe 'WORKER_HASH_MISMATCH'}
 $err=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$err)
 if($err -and $err.Count -gt 0){StopSafe 'PS2_PARSE_FAILED'}
 'PHONE_STAGE_WORKER_VERIFIED=PASS'
 $phase='TASK_REGISTRATION'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sched.NewTask(0)
 $def.RegistrationInfo.Description='One-time TEST NewBase phone snapshot into isolated SQLite on SRV only'
 $def.Principal.UserId=$account;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT60M';$def.Settings.MultipleInstances=2
 $act=$def.Actions.Create(0);$act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($name,$def,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){StopSafe 'TRIGGERS_PRESENT'}
 $phase='START'
 $null=$task.Run($null)
 'PHONE_STAGE_TASK=STARTED'
 'PHONE_STAGE_STATUS_FILE='+$done
 'CRM_WRITES=0'
 'ONEC_WRITES=0'
 'CUSTOMERS_DB_WRITES=0'
 'RESULT=STARTED;STAGE=PHONE_STAGE_SRV_LOCAL_V2'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^PHONE_STAGE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=PHONE_STAGE_SRV_LOCAL_V2;GATE='+$gate+';PHASE='+$phase
 exit 1
}
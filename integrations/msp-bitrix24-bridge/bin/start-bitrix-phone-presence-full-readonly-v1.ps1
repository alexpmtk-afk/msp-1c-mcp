#requires -version 2
# One-shot mapped Bitrix phone-presence full read-only audit, physical SRV LOCAL SERVICE.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function StopSafe([string]$Code){throw ('PHONE_FULL_AUDIT_'+$Code)}
function Sha256([string]$Path){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){StopSafe 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){StopSafe 'PS2_X64_REQUIRED'}
 $who=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){StopSafe 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $pilot=Join-Path $root 'state\bitrix-phone-existing-fields-probe-v1.status'
 $snapshot=Join-Path $root 'state\customer-phone-snapshot-v2.status'
 $import=Join-Path $root 'state\bitrix-initial-all-buyers-v5.status'
 $report=Join-Path $root 'state\bitrix-phone-presence-audit-v1.status'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $core=Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1'
 $main=Join-Path $root 'data\customers.db'
 $phone=Join-Path $root 'data\phone-source-newbase-v1.sqlite'
 foreach($f in @($pilot,$snapshot,$import,$curl,$ca,$core,$main,$phone)){
  if(-not [IO.File]::Exists($f)){StopSafe 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){StopSafe 'REPARSE_DENIED'}
 }
 if([IO.File]::Exists($report)){StopSafe 'AUDIT_ALREADY_EXECUTED'}
 $accepted=[IO.File]::ReadAllText($pilot,[Text.Encoding]::ASCII).Trim()
 if($accepted -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;PILOT_CARDS=2;CRM_ORIGINS_VERIFIED=2;CONTACT_FM=ARRAY;CONTACT_PHONE_FIELDS=0;COMPANY_FM=ARRAY;COMPANY_PHONE_FIELDS=0;ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;PHONE_DB_WRITES=0;PII_EXPORTED=0$'){StopSafe 'PILOT_NOT_ACCEPTED'}
 $source=[IO.File]::ReadAllText($snapshot,[Text.Encoding]::ASCII).Trim()
 if($source -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;ACTIVE_BUYERS=6433;CONTACT_ROWS=10751;MATCHED_BUYER_ROWS=9975;OTHER_ROWS=776;PHONE_NUMBER_ROWS=4068;PHONE_WITHOUT_CODES_ROWS=3468;DISPLAY_ROWS=9973;PHONE_TYPE_ROWS=4068;PHONE_CANDIDATE_ROWS=4068;BUYERS_WITH_PHONE=4067;BUYERS_MULTIPLE_PHONES=1;PAGES=108;ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;STAGING_DB_WRITES=YES;PII_EXPORTED=0$'){StopSafe 'PHONE_SOURCE_NOT_ACCEPTED'}
 $initial=[IO.File]::ReadAllText($import,[Text.Encoding]::ASCII).Trim()
 if($initial -notmatch '^UTC=[^;]+;STATUS=PASS_WITH_FIELD_REVIEW;MAPPED=6433;TARGET=6433;FIELDS_REVIEW=2254;NAMES_REVIEW=123;SOURCE=TEST_NEWBASE;AUTO_UPDATE=OFF;ONEC_WRITES=0$'){StopSafe 'INITIAL_SOURCE_CHANGED'}
 $phase='SCHEDULER'
 $sch=New-Object -ComObject Schedule.Service;$sch.Connect();$folder=$sch.GetFolder('\')
 $pilotTask=$folder.GetTask('MspBitrixPhoneFieldsReadOnlyPilotV1')
 $snapTask=$folder.GetTask('MspNewbasePhoneSnapshotLocalV2')
 if($null -eq $pilotTask -or [int]$pilotTask.State -ne 3 -or [int]$pilotTask.LastTaskResult -ne 0 -or $pilotTask.Definition.Triggers.Count -ne 0){StopSafe 'PILOT_TASK_NOT_IDLE_PASS'}
 if($null -eq $snapTask -or [int]$snapTask.State -ne 3 -or [int]$snapTask.LastTaskResult -ne 0){StopSafe 'SNAPSHOT_TASK_NOT_IDLE_PASS'}
 $taskName='MspBitrixPhonePresenceFullReadOnlyV1'
 $existing=$null;try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){StopSafe 'TASK_ALREADY_EXISTS'}
 $phase='FETCH_WORKER_PINNED'
 $dir=Join-Path $root 'staging\bitrix-phone-full-audit-v1'
 if([IO.Directory]::Exists($dir)){StopSafe 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'audit-bitrix-phone-presence-full-readonly-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/82774daa55266e468cd2cd592806cbfa2fbcb15b/integrations/msp-bitrix24-bridge/bin/audit-bitrix-phone-presence-full-readonly-v1.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){StopSafe 'DOWNLOAD_FAILED'}
 if((Sha256 $worker) -ne '9ee34849b7062e8d0b319b76f62c74a3231281e75aafb86c83f0058bc711546d'){StopSafe 'WORKER_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){StopSafe 'WORKER_PS2_PARSE_FAILED'}
 'FULL_AUDIT_WORKER_VERIFIED=PASS'
 $phase='REGISTER_ONE_SHOT'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sch.NewTask(0)
 $def.RegistrationInfo.Description='READONLY 4067 mapped source-phone buyer cards: Bitrix fm aggregate presence check; no PII output'
 $def.Principal.UserId=$service;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT4H';$def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0)
 $action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$service,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){StopSafe 'TRIGGERS_PRESENT'}
 $phase='RUN_ONCE'
 $null=$task.Run($null)
 'FULL_AUDIT_TASK=STARTED'
 'FULL_AUDIT_STATUS_FILE='+$report
 'SOURCE=TEST_NEWBASE'
 'CRM_MODE=READ_ONLY'
 'ONEC_WRITES=0'
 'CRM_WRITES=0'
 'CUSTOMERS_DB_WRITES=0'
 'PHONE_DB_WRITES=0'
 'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=BITRIX_PHONE_PRESENCE_FULL_READONLY_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^PHONE_FULL_AUDIT_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=BITRIX_PHONE_PRESENCE_FULL_READONLY_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

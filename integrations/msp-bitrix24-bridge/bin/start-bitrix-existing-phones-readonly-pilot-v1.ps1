#requires -version 2
# Read-only 2-card Bitrix phone field pilot, one-shot LOCAL SERVICE on SRV.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function FailSafe([string]$Code){throw ('BITRIX_PHONE_PILOT_'+$Code)}
function SHA([string]$Path){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){FailSafe 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){FailSafe 'PS2_X64_REQUIRED'}
 $who=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){FailSafe 'ADMIN_REQUIRED'}
 $base='C:\ProgramData\MspCustomerStore'
 $receipt=Join-Path $base 'state\customer-phone-snapshot-v2.status'
 $newReceipt=Join-Path $base 'state\bitrix-phone-existing-fields-probe-v1.status'
 $data=Join-Path $base 'data\phone-source-newbase-v1.sqlite'
 $curl=Join-Path $base 'bin\curl.exe'
 $ca=Join-Path $base 'config\curl-ca-bundle.crt'
 $core=Join-Path $base 'bin\msp-newbase-bitrix-core-v2.ps1'
 foreach($f in @($receipt,$data,$curl,$ca,$core)){
  if(-not [IO.File]::Exists($f)){FailSafe 'REQUIRED_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){FailSafe 'REPARSE_DENIED'}
 }
 if([IO.File]::Exists($newReceipt)){FailSafe 'PILOT_ALREADY_EXECUTED'}
 $v=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 if($v -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;ACTIVE_BUYERS=6433;CONTACT_ROWS=10751;MATCHED_BUYER_ROWS=9975;OTHER_ROWS=776;PHONE_NUMBER_ROWS=4068;PHONE_WITHOUT_CODES_ROWS=3468;DISPLAY_ROWS=9973;PHONE_TYPE_ROWS=4068;PHONE_CANDIDATE_ROWS=4068;BUYERS_WITH_PHONE=4067;BUYERS_MULTIPLE_PHONES=1;PAGES=108;ONEC_WRITES=0;CRM_WRITES=0;CUSTOMERS_DB_WRITES=0;STAGING_DB_WRITES=YES;PII_EXPORTED=0$'){FailSafe 'SNAPSHOT_PASS_NOT_CONFIRMED'}
 $sch=New-Object -ComObject Schedule.Service;$sch.Connect()
 $folder=$sch.GetFolder('\')
 $prev=$folder.GetTask('MspNewbasePhoneSnapshotLocalV2')
 if($null -eq $prev -or [int]$prev.State -ne 3 -or [int]$prev.LastTaskResult -ne 0 -or $prev.Definition.Triggers.Count -ne 0){FailSafe 'SNAPSHOT_TASK_NOT_IDLE_PASS'}
 $name='MspBitrixPhoneFieldsReadOnlyPilotV1'
 $task=$null;try{$task=$folder.GetTask($name)}catch{}
 if($null -ne $task){FailSafe 'PILOT_TASK_ALREADY_EXISTS'}
 $phase='GET_VERIFIED_WORKER'
 $dir=Join-Path $base 'staging\bitrix-phone-readonly-pilot-v1'
 if([IO.Directory]::Exists($dir)){FailSafe 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'probe-bitrix-existing-phones-readonly-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/a295d05e9d1a5697f3bcebe5e5cd3d58f405d38e/integrations/msp-bitrix24-bridge/bin/probe-bitrix-existing-phones-readonly-v1.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){FailSafe 'DOWNLOAD_FAILED'}
 if((SHA $worker) -ne 'd358c0cfc63da080730cb7b4c597069e0c42f3b805e9ad792f4eec72f9bdec77'){FailSafe 'WORKER_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){FailSafe 'WORKER_PS2_PARSE_FAILED'}
 'BITRIX_PHONE_PILOT_WORKER_VERIFIED=PASS'
 $phase='REGISTER_ONE_SHOT_TASK'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sch.NewTask(0)
 $def.RegistrationInfo.Description='TEST NewBase mapped phone-eligible company and contact: Bitrix CRM native fm read-only pilot'
 $def.Principal.UserId=$account;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT20M';$def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0);$action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($name,$def,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){FailSafe 'UNEXPECTED_TRIGGERS'}
 $phase='START_ONE_SHOT_PILOT'
 $null=$task.Run($null)
 'BITRIX_PHONE_PILOT_TASK=STARTED'
 'BITRIX_PHONE_PILOT_STATUS_FILE='+$newReceipt
 'ONEC_WRITES=0'
 'CRM_WRITES=0'
 'CUSTOMERS_DB_WRITES=0'
 'PHONE_DB_WRITES=0'
 'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=BITRIX_PHONE_FIELDS_READONLY_PILOT_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^BITRIX_PHONE_PILOT_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=BITRIX_PHONE_FIELDS_READONLY_PILOT_V1;GATE='+$gate+';PHASE='+$phase
 exit 1
}
#requires -version 2
# One-time, manual initial CRM import of 6433 TEST NewBase buyers; no automatic triggers.
# Never modifies 1C, working MSP tasks or existing installed PowerShell workers.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Reason){throw ('BULK_START_'+$Reason)}
function Digest([string]$File){
 $sha=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$sha.Clear()}
}
function CheckScript([string]$File,[string]$Expected){
 if(-not [IO.File]::Exists($File)){Fail 'SCRIPT_MISSING'}
 if((Digest $File) -ne $Expected){Fail 'SCRIPT_SHA256_MISMATCH'}
 $errors=$null
 $content=[IO.File]::ReadAllText($File,[Text.Encoding]::ASCII)
 $null=[System.Management.Automation.PSParser]::Tokenize($content,[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'SCRIPT_PS2_PARSE_FAILED'}
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $db=Join-Path $root 'data\customers.db'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 $secret=Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'
 foreach($f in @($curl,$ca,$db,$sqlite,$secret)){
  if(-not [IO.File]::Exists($f)){Fail 'PREREQUISITE_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_PREREQUISITE_DENIED'}
 }
 $snapshot=@(& $sqlite -readonly -batch -bail $db "SELECT count(*)||':'||sum(onec_type='LEGAL')||':'||sum(onec_type='PERSON')||':'||sum(onec_type='REVIEW') FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;" 2>&1)
 if($LASTEXITCODE -ne 0 -or ($snapshot -join '').Trim() -ne '6433:1941:4486:6'){Fail 'SOURCE_SNAPSHOT_NOT_6433'}
 $sch=New-Object -ComObject Schedule.Service
 $sch.Connect()
 $folder=$sch.GetFolder('\')
 $main=$folder.GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'MAIN_CUSTOMER_TASK_MISSING'}
 foreach($t in $main.Definition.Triggers){if($t.Enabled){Fail 'MAIN_TASK_AUTOSTART_CHANGED'}}
 $previous=Join-Path $root 'state\bitrix-initial-all-buyers-v3.status'
 if(-not [IO.File]::Exists($previous)){Fail 'V3_FAILURE_RECEIPT_MISSING'}
 $v3=[IO.File]::ReadAllText($previous,[Text.Encoding]::ASCII).Trim()
 if($v3 -notmatch '^UTC=[^;]+;STATUS=FAIL;GATE=CRM_VISIBLE_NAME_MISMATCH;PHASE=VERIFY_EXISTING;EXCEPTION_TYPE=RUNTIMEEXCEPTION;ERROR_ID=NEWBASE_CRM_VISIBLE_NAME_MISMATCH;ERROR_LINE=[0-9]+;MAPPED=45;TARGET=6433$'){
  Fail 'V3_FAILURE_RECEIPT_CHANGED'
 }
 $priorTask=$folder.GetTask('MspNewBaseInitialImportV3')
 if($null -eq $priorTask){Fail 'V3_TASK_MISSING'}
 if([int]$priorTask.State -eq 4 -or $priorTask.Definition.Triggers.Count -ne 0){Fail 'V3_TASK_NOT_IDLE'}
 $counts=@(& $sqlite -readonly -batch -bail $db "SELECT (SELECT count(*) FROM msp_initial_map)||':'||(SELECT count(*) FROM msp_initial_inflight);" 2>&1)
 if($LASTEXITCODE -ne 0 -or ($counts -join '').Trim() -ne '45:0'){Fail 'LOCAL_45_ZERO_INFLIGHT_CHANGED'}
 'INITIAL_V4_SAFE_RESUME_GATE=PASS'
 $taskName='MspNewBaseInitialImportV4'
 $existing=$null
 try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){Fail 'IMPORT_TASK_ALREADY_PRESENT'}
 $phase='DOWNLOAD_IMMUTABLE_PACKAGE'
 $staging=Join-Path $root 'staging\bitrix-initial-6433-v4'
 if([IO.Directory]::Exists($staging)){Fail 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($staging)
 $base='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/48b4a0a4f81a63a317fdf0cb9e88903a8c5f7e72/integrations/msp-bitrix24-bridge/bin/'
 $w=Join-Path $staging 'import-all-newbase-buyers-once-v4.ps1'
 $c=Join-Path $staging 'msp-newbase-bitrix-core-v2.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $w ($base+'import-all-newbase-buyers-once-v4.ps1')
 if($LASTEXITCODE -ne 0){Fail 'WORKER_DOWNLOAD_FAILED'}
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $c ($base+'msp-newbase-bitrix-core-v2.ps1')
 if($LASTEXITCODE -ne 0){Fail 'CORE_DOWNLOAD_FAILED'}
 CheckScript $w '541bf0d17e3a2de1add5fcd5046323a5b50e0f56a856679200b791d60428ec85'
 CheckScript $c '6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852'
 'INITIAL_BULK_PACKAGE_SHA256=PASS'
 $phase='REGISTER_ONE_TIME_TASK'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sch.NewTask(0)
 $def.RegistrationInfo.Description='One-time TEST NewBase 6433 buyer CRM load, manual no recurring triggers'
 $def.Principal.UserId=$service
 $def.Principal.LogonType=5
 $def.Principal.RunLevel=0
 $def.Settings.Enabled=$true
 $def.Settings.ExecutionTimeLimit='PT6H'
 $def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0)
 $action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$w+'" -ExpectedComputerName SRV -MaxBatches 800 -BatchSize 10'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$service,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($task.Definition.Triggers.Count -ne 0){Fail 'TASK_HAS_TRIGGERS'}
 if($task.Definition.Principal.LogonType -ne 5){Fail 'TASK_IDENTITY_INVALID'}
 $phase='START_ONCE'
 $null=$task.Run($null)
 'INITIAL_IMPORT_TASK=STARTED'
 'INITIAL_IMPORT_SOURCE=TEST_NEWBASE_SQLITE'
 'EXPECTED_SOURCE_ROWS=6433'
 'AUTO_UPDATE=OFF'
 'WORKING_1C_WRITES=0'
 'NEW_TASK_TRIGGERS=0'
 'STATUS_FILE=C:\ProgramData\MspCustomerStore\state\bitrix-initial-all-buyers-v4.status'
 'RESULT=PASS;STAGE=INITIAL_6433_IMPORT_TASK_STARTED'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^BULK_START_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=INITIAL_6433_IMPORT_TASK_STARTED;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}

#requires -version 2
# One-shot 1C TEST OData $metadata survey for phone coverage for active buyers, aggregate-only.
# No customer data export, CRM calls, 1C or SQLite changes, and no triggers.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('PHONE_SURVEY_'+$Code)}
function Sha([string]$Path){
 $s=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($s.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
 finally{$s.Clear()}
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $who=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 $db=Join-Path $root 'data\customers.db'
 $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 $status=Join-Path $root 'state\customer-phone-coverage-readonly-v2.txt'
 $import=Join-Path $root 'state\bitrix-initial-all-buyers-v5.status'
 foreach($file in @($curl,$ca,$sqlite,$db,$secret,$import)){
  if(-not [IO.File]::Exists($file)){Fail 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DENIED'}
 }
 if([IO.File]::Exists($status)){Fail 'STATUS_ALREADY_EXISTS'}
 $old=[IO.File]::ReadAllText($import,[Text.Encoding]::ASCII).Trim()
 if($old -notmatch '^UTC=[^;]+;STATUS=PASS_WITH_FIELD_REVIEW;MAPPED=6433;TARGET=6433;FIELDS_REVIEW=[0-9]+;NAMES_REVIEW=[0-9]+;SOURCE=TEST_NEWBASE;AUTO_UPDATE=OFF;ONEC_WRITES=0$'){Fail 'IMPORT_NOT_FINAL'}
 $count=@(& $sqlite -readonly -batch -bail $db "SELECT count(*)||':'||(SELECT count(*) FROM msp_initial_map)||':'||(SELECT count(*) FROM msp_initial_inflight) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;" 2>&1)
 if($LASTEXITCODE -ne 0 -or ($count -join '').Trim() -ne '6433:6433:0'){Fail 'LOCAL_IMPORT_STATE_CHANGED'}
 $sch=New-Object -ComObject Schedule.Service;$sch.Connect()
 $folder=$sch.GetFolder('\')
 $oldTask=$folder.GetTask('MspNewBaseInitialImportV5')
 if($null -eq $oldTask -or [int]$oldTask.State -ne 3){Fail 'IMPORT_TASK_NOT_IDLE'}
 $metadataPath=Join-Path $root 'state\customer-phone-contactinfo-metadata-v3.txt'
 if(-not [IO.File]::Exists($metadataPath)){Fail 'METADATA_V3_RECEIPT_MISSING'}
 $metadata=[IO.File]::ReadAllText($metadataPath,[Text.Encoding]::ASCII)
 if($metadata -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;ENTITY_SETS=1492;CONTACTINFO_SET=YES;ORIGIN=PART_ENTITY_SET;'){Fail 'METADATA_V3_NOT_ACCEPTED'}
 $prior=$folder.GetTask('MspNewbasePhoneMetadataProbeV3')
 if($null -eq $prior -or [int]$prior.State -ne 3 -or $prior.Definition.Triggers.Count -ne 0){Fail 'METADATA_TASK_NOT_IDLE'}
 'PHONE_COVERAGE_SAFE_GATE=PASS'
 $failed=Join-Path $root 'state\customer-phone-coverage-readonly-v1.txt'
 if(-not [IO.File]::Exists($failed)){Fail 'V1_FAILURE_RECEIPT_MISSING'}
 $receipt=[IO.File]::ReadAllText($failed,[Text.Encoding]::ASCII).Trim()
 if($receipt -ne 'STATUS=FAIL;SOURCE=TEST_NEWBASE;PHASE=CONTACT_COUNT_BEFORE;GATE=HTTP_406;PII_EXPORTED=0'){Fail 'V1_FAILURE_RECEIPT_CHANGED'}
 $priorTask=$folder.GetTask('MspNewbasePhoneCoverageReadOnlyV1')
 if($null -eq $priorTask -or [int]$priorTask.State -ne 3 -or $priorTask.Definition.Triggers.Count -ne 0){Fail 'V1_TASK_NOT_IDLE'}
 'PHONE_COVERAGE_V2_RECOVERY_GATE=PASS'
 $taskName='MspNewbasePhoneCoverageReadOnlyV2'
 $existing=$null;try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){Fail 'TASK_ALREADY_EXISTS'}
 $phase='GET_PINNED_READONLY_WORKER'
 $dir=Join-Path $root 'staging\phone-coverage-v2'
 if([IO.Directory]::Exists($dir)){Fail 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'audit-newbase-phone-coverage-readonly-v2.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/0c7726725d03b8d6f1092617280bf8770df08111/integrations/msp-bitrix24-bridge/bin/audit-newbase-phone-coverage-readonly-v2.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Fail 'DOWNLOAD_FAILED'}
 if((Sha $worker) -ne 'c48effdfe507364cbb9cca45344b0184f4445a63c888fe2bb20725eadef5d2c1'){Fail 'WORKER_HASH_MISMATCH'}
 $errs=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errs)
 if($errs -and $errs.Count -gt 0){Fail 'WORKER_PS2_PARSE_FAILED'}
 'PHONE_COVERAGE_WORKER_SHA256=PASS'
 $phase='REGISTER_ONE_SHOT_LOCAL_SERVICE'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sch.NewTask(0)
 $def.RegistrationInfo.Description='READONLY TEST NewBase contact-info OData GET full aggregate coverage, no data export, one-shot'
 $def.Principal.UserId=$service;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT45M';$def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0);$action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$service,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){Fail 'TRIGGERS_NOT_ZERO'}
 $phase='START_READONLY_SURVEY'
 $null=$task.Run($null)
 'PHONE_COVERAGE_TASK=STARTED'
 'PHONE_COVERAGE_STATUS_FILE='+$status
 'ONEC_REQUESTS=CONTACT_PAGE_GET_ONLY'
 'BITRIX_REQUESTS=0'
 'CUSTOMER_EXPORT=0'
 'AUTO_UPDATE=OFF'
 'COVERAGE_WORKER_STARTED=YES'
 'COVERAGE_DATA_EXPORTED=NO'
 'COVERAGE_PROGRESS_FILE='+$status
 'RESULT=STARTED;STAGE=PHONE_COVERAGE_READONLY_V2_TASK_STARTED'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^PHONE_SURVEY_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=PHONE_COVERAGE_READONLY_V2_TASK_STARTED;GATE='+$gate+';PHASE='+$phase
 exit 1
}

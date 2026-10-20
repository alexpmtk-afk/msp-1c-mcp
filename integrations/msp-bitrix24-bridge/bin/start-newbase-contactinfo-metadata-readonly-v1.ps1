#requires -version 2
# One-shot 1C TEST OData $metadata survey for contact-information schema only.
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
 $status=Join-Path $root 'state\customer-phone-contactinfo-metadata-v1.txt'
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
 $taskName='MspNewbasePhoneMetadataProbeV1'
 $existing=$null;try{$existing=$folder.GetTask($taskName)}catch{}
 if($null -ne $existing){Fail 'TASK_ALREADY_EXISTS'}
 $phase='GET_PINNED_READONLY_WORKER'
 $dir=Join-Path $root 'staging\phone-metadata-v1'
 if([IO.Directory]::Exists($dir)){Fail 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'probe-newbase-contactinfo-metadata-readonly-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/0da5d9a1a9713ca8abedcf271bfd4eea4190ccf8/integrations/msp-bitrix24-bridge/bin/probe-newbase-contactinfo-metadata-readonly-v1.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Fail 'DOWNLOAD_FAILED'}
 if((Sha $worker) -ne '2c06a6e9148e10c420aab77f6e7034b4e3eb0c30f91ea06627938a21a1ac8e01'){Fail 'WORKER_HASH_MISMATCH'}
 $errs=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errs)
 if($errs -and $errs.Count -gt 0){Fail 'WORKER_PS2_PARSE_FAILED'}
 'PHONE_METADATA_WORKER_SHA256=PASS'
 $phase='REGISTER_ONE_SHOT_LOCAL_SERVICE'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sch.NewTask(0)
 $def.RegistrationInfo.Description='READONLY TEST NewBase contact-information OData metadata GET, no customer rows, one-shot'
 $def.Principal.UserId=$service;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT3M';$def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0);$action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$service,$null,5,$null)
 $task=$folder.GetTask($taskName)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){Fail 'TRIGGERS_NOT_ZERO'}
 $phase='START_READONLY_SURVEY'
 $null=$task.Run($null)
 'PHONE_METADATA_TASK=STARTED'
 'PHONE_METADATA_STATUS_FILE='+$status
 'ONEC_REQUESTS=METADATA_GET_ONLY'
 'BITRIX_REQUESTS=0'
 'CUSTOMER_EXPORT=0'
 'AUTO_UPDATE=OFF'
 $verified=$false
 for($i=0;$i -lt 90;$i++){
  if([IO.File]::Exists($status)){
   $receipt=@([IO.File]::ReadAllLines($status,[Text.Encoding]::ASCII))
   if($receipt.Length -gt 0 -and $receipt[0] -match '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;'){
    foreach($line in $receipt){Write-Output $line}
    $verified=$true
    break
   }
   if($receipt.Length -gt 0 -and $receipt[0] -match '^STATUS=FAIL;'){foreach($line in $receipt){Write-Output $line};Fail 'METADATA_WORKER_FAILED'}
  }
  Start-Sleep -Seconds 1
 }
 if($verified){'RESULT=PASS;STAGE=PHONE_METADATA_READONLY_ACCEPTED'}else{'RESULT=STARTED;STAGE=PHONE_METADATA_READONLY_AWAITING_RECEIPT'}
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^PHONE_SURVEY_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=PHONE_METADATA_READONLY_TASK_STARTED;GATE='+$gate+';PHASE='+$phase
 exit 1
}

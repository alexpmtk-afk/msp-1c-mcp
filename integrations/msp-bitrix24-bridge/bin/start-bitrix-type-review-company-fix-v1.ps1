#requires -version 2
# Administrator-controlled one-shot launcher, six TEST NewBase mapped companies only.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function Gate([string]$Why){throw ('TYPE_REVIEW_FIX_'+$Why)}
function Hash([string]$Path){$h=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){Gate 'HOST_DENIED'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Gate 'PS2_X64_REQUIRED'}
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $id
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Gate 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $status=Join-Path $root 'state\msp-bitrix-type-review-company-fix-v1.status'
 $journal=Join-Path $root 'state\msp-bitrix-type-review-company-fix-v1.journal'
 $backup=Join-Path $root 'data\customers.before-type-review-company-fix-v1.sqlite.bak'
 $proof=Join-Path $root 'state\msp-bitrix-unnamed-name-drain-v1.status'
 foreach($f in @($status,$journal,$backup)){if([IO.File]::Exists($f)){Gate 'PREVIOUS_ATTEMPT_PRESENT'}}
 foreach($f in @($proof,(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'data\customers.db'),(Join-Path $root 'bin\curl.exe'),(Join-Path $root 'config\curl-ca-bundle.crt'),(Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1'),(Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'))){
  if(-not [IO.File]::Exists($f)){Gate 'REQUIRED_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Gate 'REPARSE_DENIED'}
 }
 if((Hash (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')) -ne '6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852'){Gate 'BITRIX_CORE_CHANGED'}
 $receipt=[IO.File]::ReadAllText($proof,[Text.Encoding]::ASCII).Trim()
 if($receipt -notmatch 'STATUS=PASS;MODE=ONESHOT;SOURCE=TEST_NEWBASE;BATCHES=27;VERIFIED=525;CRM_WRITES=525;DONE=546;PENDING=0;INTENT=0;UNCERTAIN=0;BACKREAD=PASS;PHONE_EMAIL_PRESERVED=PASS;SQLITE_QUICK_CHECK=OK;ELAPSED_SECONDS=[0-9]+;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'){Gate 'NAME_DRAIN_NOT_ACCEPTED'}
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $aggregate=& $exe -readonly -batch -bail $db "SELECT count(*)||':'||count(DISTINCT m.crm_id)||':'||coalesce(sum(CASE WHEN length(trim(coalesce(c.name_full,'')))>0 AND length(trim(coalesce(c.person_name,'')))=0 THEN 1 ELSE 0 END),0)||':'||coalesce(sum(CASE WHEN length(trim(coalesce(c.inn,'')))>0 THEN 1 ELSE 0 END),0) FROM customers c JOIN msp_initial_map m ON m.onec_guid=c.onec_guid WHERE c.onec_type='REVIEW' AND c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND m.entity_kind=4;"
 if($LASTEXITCODE -ne 0 -or [string]$aggregate -ne '6:6:6:1'){Gate 'SIX_SOURCE_SET_CHANGED'}
 $integrity=& $exe -readonly -batch -bail $db 'PRAGMA quick_check;'
 if($LASTEXITCODE -ne 0 -or [string]$integrity -ne 'ok'){Gate 'SQLITE_INTEGRITY'}
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect();$folder=$sched.GetFolder('\')
 $name='MspBitrixTypeReviewCompanyFixV1'
 $existing=$null;try{$existing=$folder.GetTask($name)}catch{}
 if($null -ne $existing){Gate 'TASK_ALREADY_EXISTS'}
 $past=$folder.GetTask('MspBitrixNameFixDrainV1')
 if($null -eq $past -or [int]$past.State -ne 3 -or [int]$past.LastTaskResult -ne 0){Gate 'LAST_NAME_TASK_NOT_PASS'}
 foreach($t in @($folder.GetTasks(0))){if($t.Name -match '^Msp(CustomerStore|Newbase|NewBase|BitrixPhone|BitrixUnnamed|BitrixName|BitrixTypeReview)' -and [int]$t.State -eq 4){Gate 'ANOTHER_RELATED_TASK_RUNNING'}}
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\bitrix-type-review-company-fix-v1'
 if([IO.Directory]::Exists($dir)){Gate 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'repair-bitrix-type-review-companies-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/a930426c99b9edbb0657582caf1bd69398a10ae2/integrations/msp-bitrix24-bridge/bin/repair-bitrix-type-review-companies-v1.ps1'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Gate 'DOWNLOAD_FAILED'}
 if((Hash $worker) -ne 'b4c7c6ada5f780e35986e466db5b9e9dc5ca0dfda41b3740cc6f575cde316166'){Gate 'WORKER_HASH_MISMATCH'}
 if(([IO.File]::GetAttributes($worker) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Gate 'WORKER_REPARSE_DENIED'}
 $errors=$null;$null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Gate 'WORKER_PS2_PARSE_FAILED'}
 'TYPE_REVIEW_WORKER_HASH=PASS'
 'SOURCE_REVIEW_COMPANIES=6'
 $phase='REGISTER'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sched.NewTask(0)
 $def.RegistrationInfo.Description='One-shot guarded six mapped Bitrix24 company title updates from TEST NewBase; no recurrence, no 1C writes.'
 $def.Principal.UserId=$account;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT45M';$def.Settings.MultipleInstances=2
 $act=$def.Actions.Create(0);$act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($name,$def,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){Gate 'TRIGGERS_PRESENT'}
 $phase='START';$null=$task.Run($null)
 'TYPE_REVIEW_TASK=STARTED'
 'STATUS_FILE='+$status
 'JOURNAL_FILE='+$journal
 'CRM_WRITES_MAX=6';'ONEC_WRITES=0';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=MSP_BITRIX_TYPE_REVIEW_COMPANY_FIX_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^TYPE_REVIEW_FIX_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_BITRIX_TYPE_REVIEW_COMPANY_FIX_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}
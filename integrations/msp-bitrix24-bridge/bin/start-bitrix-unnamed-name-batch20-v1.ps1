#requires -version 2
# Install + start one no-trigger 20-contact Bitrix24 placeholder-name correction task.
# Admin setup only; CRM worker runs as LOCAL SERVICE, has no automatic scheduling.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function FailGate([string]$Code){throw ('NAME_BATCH20_'+$Code)}
function Sha([string]$Path){$h=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}}
try{
 if($ExpectedComputerName -ne 'SRV' -or $env:COMPUTERNAME -ne 'SRV'){FailGate 'HOST_INVALID'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){FailGate 'PS2_X64_REQUIRED'}
 $who=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){FailGate 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $pilot=Join-Path $root 'state\msp-bitrix-unnamed-fix-pilot-v1.status'
 $status=Join-Path $root 'state\msp-bitrix-unnamed-fix-batch20-v1.status'
 if([IO.File]::Exists($status)){FailGate 'ALREADY_ATTEMPTED'}
 foreach($rel in @('data\customers.db','state\msp-bitrix-unnamed-fix-pilot-v1.status','bin\sqlite3.exe','bin\curl.exe','config\curl-ca-bundle.crt','bin\msp-newbase-bitrix-core-v2.ps1','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi')){
  $f=Join-Path $root $rel
  if(-not [IO.File]::Exists($f)){FailGate 'INPUT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){FailGate 'REPARSE_DENIED'}
 }
 $proof=[IO.File]::ReadAllText($pilot,[Text.Encoding]::ASCII).Trim()
 if($proof -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;MODE=Pilot;TARGET=546;VERIFIED=1;PENDING=545;UNCERTAIN=0;CRM_WRITES=1;BACKREAD=PASS;NAME_SOURCE=name_short;PHONE_EMAIL_PRESERVED=PASS;ONEC_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0$'){FailGate 'PILOT_NOT_ACCEPTED'}
 if((Sha (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')) -ne '6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852'){FailGate 'BITRIX_CORE_CHANGED'}
 $sch=New-Object -ComObject Schedule.Service;$sch.Connect();$folder=$sch.GetFolder('\')
 $prev=$folder.GetTask('MspBitrixNameFixPilotV1')
 if($null -eq $prev -or [int]$prev.State -ne 3 -or [int]$prev.LastTaskResult -ne 0){FailGate 'PILOT_TASK_NOT_DONE'}
 $name='MspBitrixNameFixBatch20V1'
 $existing=$null;try{$existing=$folder.GetTask($name)}catch{}
 if($null -ne $existing){FailGate 'TASK_ALREADY_EXISTS'}
 foreach($t in @($folder.GetTasks(0))){
  if($t.Name -match '^Msp(CustomerStore|Newbase|NewBase|BitrixPhone|BitrixUnnamed|BitrixName)' -and [int]$t.State -eq 4){FailGate 'TASK_CONCURRENT'}
 }
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\bitrix-name-fix-batch20-v1'
 if([IO.Directory]::Exists($dir)){FailGate 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'repair-bitrix-unnamed-name-batch20-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/92e99a141e7e5a7c185636577f05e9fd7e5a5f7b/integrations/msp-bitrix24-bridge/bin/repair-bitrix-unnamed-name-batch20-v1.ps1'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){FailGate 'DOWNLOAD_FAILED'}
 if((Sha $worker) -ne 'b997ad9ea4e7d57417862309db08133b2c9bc4f78ee294925d05bf0045b995e4'){FailGate 'WORKER_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){FailGate 'PS2_PARSE_FAILED'}
 'NAME_BATCH20_WORKER_VERIFIED=PASS'
 $phase='REGISTER'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$sch.NewTask(0)
 $definition.RegistrationInfo.Description='Single 20-card 1C name_short repair batch, identity/backread, preserve CRM phones/emails/comments'
 $definition.Principal.UserId=$account;$definition.Principal.LogonType=5;$definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true;$definition.Settings.ExecutionTimeLimit='PT45M';$definition.Settings.MultipleInstances=2
 $act=$definition.Actions.Create(0);$act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV -MaxCards 20'
 $null=$folder.RegisterTaskDefinition($name,$definition,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){FailGate 'TRIGGERS_PRESENT'}
 $phase='START';$null=$task.Run($null)
 'NAME_BATCH20_TASK=STARTED';'NAME_BATCH20_STATUS_FILE='+$status
 'CRM_WRITES_MAX=20';'ONEC_WRITES=0';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=MSP_BITRIX_NAME_BATCH20_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NAME_BATCH20_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_BITRIX_NAME_BATCH20_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

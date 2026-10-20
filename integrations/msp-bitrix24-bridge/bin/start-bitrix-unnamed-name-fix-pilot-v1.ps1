#requires -version 2
# One-time administrator launch of 1-contact Bitrix name correction under LOCAL SERVICE.
# Source: successful read-only 546 audit. Immutable code hash; no repeating triggers.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function StopSafe([string]$Code){throw ('UNNAMED_FIX_'+$Code)}
function Sha([string]$Path){$h=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}}
try{
 if($ExpectedComputerName -ne 'SRV' -or $env:COMPUTERNAME -ne 'SRV'){StopSafe 'HOST_INVALID'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){StopSafe 'PS2_X64_ONLY'}
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){StopSafe 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $receipt=Join-Path $root 'state\msp-bitrix-unnamed-fix-pilot-v1.status'
 $audit=Join-Path $root 'state\bitrix-unnamed-names-audit-v1.status'
 $backup=Join-Path $root 'data\customers.before-unnamed-fix-v1.sqlite.bak'
 if([IO.File]::Exists($receipt) -or [IO.File]::Exists($backup)){StopSafe 'PILOT_ALREADY_ATTEMPTED'}
 foreach($rel in @('data\customers.db','state\bitrix-unnamed-names-audit-v1.status','bin\curl.exe','bin\sqlite3.exe','config\curl-ca-bundle.crt','bin\msp-newbase-bitrix-core-v2.ps1','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi')){
  $file=Join-Path $root $rel
  if(-not [IO.File]::Exists($file)){StopSafe 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){StopSafe 'REPARSE_DENIED'}
 }
 if((Sha (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')) -ne '6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852'){StopSafe 'CORE_HASH_INVALID'}
 if([IO.File]::ReadAllText($audit,[Text.Encoding]::ASCII).Trim() -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;SCANNED=546;PLACEHOLDER=546;ALREADY_NAMED=0;DIFFERENT_NAME=0;OTHER_FIO_PARTS=0;DUPLICATE_ORIGIN=0;IDENTITY_PROBLEMS=0;CRM_READ_ERRORS=0;BATCHES=55;CRM_WRITES=0;ONEC_WRITES=0;SQLITE_WRITES=0;PII_EXPORTED=0$'){StopSafe 'AUDIT_NOT_ACCEPTED'}
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect();$folder=$sched.GetFolder('\')
 $at=$folder.GetTask('MspBitrixUnnamedNamesAuditV1')
 if($null -eq $at -or [int]$at.State -ne 3 -or [int]$at.LastTaskResult -ne 0){StopSafe 'AUDIT_TASK_NOT_PASS'}
 $name='MspBitrixNameFixPilotV1'
 $previous=$null;try{$previous=$folder.GetTask($name)}catch{}
 if($null -ne $previous){StopSafe 'TASK_ALREADY_EXISTS'}
 foreach($t in @($folder.GetTasks(0))){if($t.Name -match '^Msp(CustomerStore|Newbase|NewBase|BitrixPhone|BitrixUnnamed|BitrixName)' -and [int]$t.State -eq 4){StopSafe 'CONCURRENT_TASK'}}
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\bitrix-name-fix-pilot-v1'
 if([IO.Directory]::Exists($dir)){StopSafe 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'repair-bitrix-unnamed-name-pilot-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/8692dfd5042da65e476411b0094b361bff0412fa/integrations/msp-bitrix24-bridge/bin/repair-bitrix-unnamed-name-pilot-v1.ps1'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){StopSafe 'DOWNLOAD_FAILED'}
 if((Sha $worker) -ne '2c643d6657f66c1b37b4c63455ac731eab78c1eaccfc843534710dea4297f9e6'){StopSafe 'WORKER_HASH_MISMATCH'}
 $errors=$null;$null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){StopSafe 'WORKER_PS2_PARSE_INVALID'}
 'NAME_FIX_WORKER_VERIFIED=PASS'
 $phase='REGISTER'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$sched.NewTask(0)
 $definition.RegistrationInfo.Description='One contact only: replace 1C placeholder display name with name_short, verify origin and preserve phones/emails'
 $definition.Principal.UserId=$account;$definition.Principal.LogonType=5;$definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true;$definition.Settings.ExecutionTimeLimit='PT30M';$definition.Settings.MultipleInstances=2
 $act=$definition.Actions.Create(0);$act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($name,$definition,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){StopSafe 'TRIGGERS_PRESENT'}
 $phase='START';$null=$task.Run($null)
 'NAME_FIX_PILOT_TASK=STARTED';'NAME_FIX_PILOT_STATUS_FILE='+$receipt
 'CRM_WRITES_MAX=1';'ONEC_WRITES=0';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=MSP_BITRIX_NAME_FIX_PILOT_V1'
}catch{
 $gate='RUNTIME_ERROR';if($_.Exception.Message -match '^UNNAMED_FIX_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_BITRIX_NAME_FIX_PILOT_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

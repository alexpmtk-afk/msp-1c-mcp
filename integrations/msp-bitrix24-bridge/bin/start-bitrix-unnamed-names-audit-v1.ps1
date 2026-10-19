#requires -version 2
# Install and launch one-shot read-only Bitrix audit of 546 placeholder-name candidates.
# Admin registers no-trigger LOCAL SERVICE task. CRM, 1C and customers.db remain unchanged.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function Gate([string]$Code){throw ('NAME_AUDIT_'+$Code)}
function Sha([string]$Path){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}
}
try{
 if($ExpectedComputerName -ne 'SRV' -or $env:COMPUTERNAME -ne 'SRV'){Gate 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Gate 'PS2_X64_ONLY'}
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Gate 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $receipt=Join-Path $root 'state\bitrix-unnamed-names-audit-v1.status'
 if([IO.File]::Exists($receipt)){Gate 'REPORT_ALREADY_EXISTS'}
 foreach($rel in @('data\customers.db','bin\sqlite3.exe','bin\curl.exe','config\curl-ca-bundle.crt','bin\msp-newbase-bitrix-core-v2.ps1','staging\bitrix-direct-private\bitrix-direct-webhook.dpapi')){
  $f=Join-Path $root $rel
  if(-not [IO.File]::Exists($f)){Gate 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Gate 'REPARSE_DENIED'}
 }
 if((Sha (Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1')) -ne '6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852'){Gate 'CORE_HASH_CHANGED'}
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect();$folder=$sched.GetFolder('\')
 $name='MspBitrixUnnamedNamesAuditV1';$old=$null
 try{$old=$folder.GetTask($name)}catch{}
 if($null -ne $old){Gate 'TASK_ALREADY_EXISTS'}
 foreach($t in @($folder.GetTasks(0))){
  if($t.Name -match '^Msp(CustomerStore|Newbase|NewBase|BitrixPhone|BitrixUnnamed)' -and [int]$t.State -eq 4){Gate 'CONCURRENT_TASK_RUNNING'}
 }
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\bitrix-unnamed-names-audit-v1'
 if([IO.Directory]::Exists($dir)){Gate 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'audit-bitrix-unnamed-names-readonly-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/eec9fb238804e0269ab18f6cc36a08beea634882/integrations/msp-bitrix24-bridge/bin/audit-bitrix-unnamed-names-readonly-v1.ps1'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Gate 'DOWNLOAD_FAILED'}
 if((Sha $worker) -ne 'e1e8d4bddf2e3729c6bbe14536d4898877f733027ff119148b3b5905796899f2'){Gate 'WORKER_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Gate 'PS2_PARSE_FAILED'}
 'NAME_AUDIT_WORKER_VERIFIED=PASS'
 $phase='REGISTER'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$sched.NewTask(0)
 $definition.RegistrationInfo.Description='Single-run read-only audit of 546 1C placeholder names and Bitrix duplicate origins; no business data output or CRM writes'
 $definition.Principal.UserId=$account;$definition.Principal.LogonType=5;$definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true;$definition.Settings.ExecutionTimeLimit='PT90M';$definition.Settings.MultipleInstances=2
 $action=$definition.Actions.Create(0);$action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($name,$definition,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){Gate 'TRIGGERS_PRESENT'}
 $phase='START';$null=$task.Run($null)
 'NAME_AUDIT_TASK=STARTED';'NAME_AUDIT_STATUS_FILE='+$receipt
 'CRM_WRITES=0';'ONEC_WRITES=0';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=BITRIX_UNNAMED_NAMES_READONLY_AUDIT_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NAME_AUDIT_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=BITRIX_UNNAMED_NAMES_READONLY_AUDIT_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

#requires -version 2
# Register a single no-trigger LOCAL SERVICE SRV customer-phone SQLite unification.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function StopSafe([string]$Code){throw ('PHONE_UNIFY_'+$Code)}
function Sha256([string]$File){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){StopSafe 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){StopSafe 'PS2_X64_REQUIRED'}
 $who=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){StopSafe 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $main=Join-Path $root 'data\customers.db'
 $phone=Join-Path $root 'data\phone-source-newbase-v1.sqlite'
 $receipt=Join-Path $root 'state\customer-unified-phones-v1.status'
 $backup=Join-Path $root 'data\customers.before-phone-unify-v1.sqlite.bak'
 $sourceReceipt=Join-Path $root 'state\customer-phone-snapshot-v2.status'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 foreach($f in @($main,$phone,$sourceReceipt,$curl,$ca,(Join-Path $root 'bin\sqlite3.exe'))){
  if(-not [IO.File]::Exists($f)){StopSafe 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){StopSafe 'REPARSE_DENIED'}
 }
 if([IO.File]::Exists($receipt) -or [IO.File]::Exists($backup)){StopSafe 'ALREADY_ATTEMPTED'}
 $sch=New-Object -ComObject Schedule.Service;$sch.Connect()
 $folder=$sch.GetFolder('\')
 $previous=$folder.GetTask('MspNewbasePhoneSnapshotLocalV2')
 if($null -eq $previous -or [int]$previous.State -ne 3 -or [int]$previous.LastTaskResult -ne 0){StopSafe 'PHONE_SOURCE_TASK_NOT_PASS'}
 foreach($task in @($folder.GetTasks(0))){
  if($task.Name -match '^Msp(CustomerStore|Newbase|NewBase)' -and [int]$task.State -eq 4){StopSafe 'SOURCE_TASK_CONCURRENT'}
 }
 $name='MspCustomerPhoneUnifyV1'
 $existing=$null;try{$existing=$folder.GetTask($name)}catch{}
 if($null -ne $existing){StopSafe 'TASK_ALREADY_EXISTS'}
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\customer-phone-unify-v1'
 if([IO.Directory]::Exists($dir)){StopSafe 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'unify-srv-customer-phones-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/ac8a3345fa94645a93094590da26d7db3c034150/integrations/msp-bitrix24-bridge/bin/unify-srv-customer-phones-v1.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){StopSafe 'DOWNLOAD_FAILED'}
 if((Sha256 $worker) -ne '119622c532190bb63b46d79150b62ce61d717b53964fdca4e58287ecc24d8736'){StopSafe 'WORKER_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){StopSafe 'WORKER_PS2_PARSE_FAILED'}
 'UNIFY_WORKER_VERIFIED=PASS'
 $phase='REGISTER_TASK'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$sch.NewTask(0)
 $definition.RegistrationInfo.Description='ONE-TIME backup and merge 4068 1C TEST source phones into existing local customers.db; no CRM/1C writes'
 $definition.Principal.UserId=$account;$definition.Principal.LogonType=5;$definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true;$definition.Settings.ExecutionTimeLimit='PT45M';$definition.Settings.MultipleInstances=2
 $act=$definition.Actions.Create(0);$act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($name,$definition,2,$account,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){StopSafe 'TRIGGERS_PRESENT'}
 $phase='START'
 $null=$task.Run($null)
 'UNIFY_TASK=STARTED'
 'UNIFY_STATUS_FILE='+$receipt
 'BACKUP_PATH='+$backup
 'ONEC_WRITES=0';'BITRIX_WRITES=0';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=SRV_CUSTOMER_PHONE_UNIFICATION_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^PHONE_UNIFY_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_CUSTOMER_PHONE_UNIFICATION_V1;GATE='+$gate+';PHASE='+$phase
 exit 1
}

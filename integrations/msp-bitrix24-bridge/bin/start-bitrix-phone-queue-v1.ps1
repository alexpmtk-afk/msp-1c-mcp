#requires -version 2
# One-shot admin launcher, prepares SRV-local Bitrix phone delta queue only (CRM write=0).
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='HOST'
function FailGate([string]$Gate){throw ('PHONE_QUEUE_'+$Gate)}
function Sha([string]$File){$h=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}}
try{
 if($ExpectedComputerName -ne 'SRV' -or $env:COMPUTERNAME -ne 'SRV'){FailGate 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){FailGate 'PS2_X64_ONLY'}
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){FailGate 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $receipt=Join-Path $root 'state\msp-bitrix-phone-queue-v1.status'
 $backup=Join-Path $root 'data\customers.before-phone-queue-v1.sqlite.bak'
 if([IO.File]::Exists($receipt) -or [IO.File]::Exists($backup)){FailGate 'ALREADY_ATTEMPTED'}
 foreach($rel in @('data\customers.db','state\customer-unified-phones-v1.status','bin\sqlite3.exe','bin\curl.exe','config\curl-ca-bundle.crt','bin\msp-newbase-bitrix-core-v2.ps1')){
  $f=Join-Path $root $rel
  if(-not [IO.File]::Exists($f) -or (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0)){FailGate 'FILE_MISSING_OR_REPARSE'}
 }
 $sch=New-Object -ComObject Schedule.Service;$sch.Connect();$folder=$sch.GetFolder('\')
 $prior=$folder.GetTask('MspCustomerPhoneUnifyV1')
 if($null -eq $prior -or [int]$prior.State -ne 3 -or [int]$prior.LastTaskResult -ne 0){FailGate 'UNIFICATION_NOT_ACCEPTED'}
 $existing=$null;try{$existing=$folder.GetTask('MspBitrixPhoneQueueV1')}catch{}
 if($null -ne $existing){FailGate 'TASK_ALREADY_EXISTS'}
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\bitrix-phone-queue-v1'
 if([IO.Directory]::Exists($dir)){FailGate 'STAGING_ALREADY_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'prepare-bitrix-phone-queue-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/18e2d95e6c90f6da421a69c60f192f1cf48d090/integrations/msp-bitrix24-bridge/bin/prepare-bitrix-phone-queue-v1.ps1'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){FailGate 'DOWNLOAD_FAILED'}
 if((Sha $worker) -ne '4fb8d496db87b3dda68b3d658419a3f0514720d45e4fea1ab7c8c08f561b2236'){FailGate 'HASH_FAILED'}
 $e=$null;$null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::ASCII),[ref]$e)
 if($e -and $e.Count -gt 0){FailGate 'PS2_PARSE_FAILED'}
 'BITRIX_PHONE_QUEUE_WORKER_VERIFIED=PASS'
 $phase='REGISTER'
 $serviceAccount=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sch.NewTask(0)
 $def.RegistrationInfo.Description='One-time local SQLite Bitrix delta queue preparation, no CRM or OneC requests'
 $def.Principal.UserId=$serviceAccount;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT30M';$def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0);$action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition('MspBitrixPhoneQueueV1',$def,2,$serviceAccount,$null,5,$null)
 $task=$folder.GetTask('MspBitrixPhoneQueueV1')
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){FailGate 'TRIGGERS_PRESENT'}
 $phase='START';$null=$task.Run($null)
 'BITRIX_PHONE_QUEUE_TASK=STARTED';'QUEUE_STATUS_FILE='+$receipt
 'CRM_WRITES=0';'ONEC_WRITES=0';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=MSP_BITRIX_PHONE_QUEUE_V1'
}catch{
 $gate='RUNTIME'
 if($_.Exception.Message -match '^PHONE_QUEUE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_BITRIX_PHONE_QUEUE_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

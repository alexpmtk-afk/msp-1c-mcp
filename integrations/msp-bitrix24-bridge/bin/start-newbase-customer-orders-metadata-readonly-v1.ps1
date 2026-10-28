#requires -version 2
# One-shot TEST NewBase OData $metadata ONLY; local Windows Task Scheduler LocalService.
# Existing 1C->Bitrix24 tasks, daily sync, gateway, CRM and SQLite are untouched.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$phase='PREFLIGHT'
function Fail([string]$Code){throw ('ONEC_ORDER_LAUNCH_'+$Code)}
function Need([bool]$Condition,[string]$Code){if(-not $Condition){Fail $Code}}
function FileGuard([string]$Path){
 Need ([IO.File]::Exists($Path)) 'FILE_MISSING'
 Need (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
}
function GitBlob([string]$Path){
 FileGuard $Path
 $data=[IO.File]::ReadAllBytes($Path)
 $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length+[char]0))
 $blob=New-Object byte[] ($header.Length+$data.Length)
 [Array]::Copy($header,0,$blob,0,$header.Length)
 [Array]::Copy($data,0,$blob,$header.Length,$data.Length)
 $alg=New-Object Security.Cryptography.SHA1Managed
 try{return ([BitConverter]::ToString($alg.ComputeHash($blob))).Replace('-','').ToLowerInvariant()}
 finally{$alg.Clear()}
}
try{
 Need ($ExpectedComputerName -eq 'SRV' -and $env:COMPUTERNAME -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 Need ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'ADMIN_REQUIRED'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $cfg=Join-Path $root 'config\collector.ini';$secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 $state=Join-Path $root 'state\bitrix-to-onec-customer-order-metadata-v1.txt'
 $dir=Join-Path $root 'staging\bitrix-to-onec-order-meta-v1'
 $worker=Join-Path $dir 'probe-newbase-customer-orders-metadata-readonly-v1.ps1'
 foreach($f in @($curl,$ca,$cfg,$secret)){FileGuard $f}
 Need ([IO.Directory]::Exists((Join-Path $root 'state'))) 'STATE_FOLDER_MISSING'
 Need (-not [IO.File]::Exists($state)) 'STATUS_ALREADY_EXISTS'
 Need (-not [IO.Directory]::Exists($dir)) 'STAGING_ALREADY_EXISTS'
 $flags=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
 foreach($key in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  Need ($flags -match ('(?m)^'+[regex]::Escape($key)+'\r?$')) 'LEGACY_CONFIG_CHANGED'
 }
 $s=New-Object -ComObject Schedule.Service;$s.Connect()
 $folder=$s.GetFolder('\')
 $taskName='MspOnecCustomerOrderMetadataReadOnlyV1'
 $existing=$null;try{$existing=$folder.GetTask($taskName)}catch{}
 Need ($null -eq $existing) 'TASK_ALREADY_EXISTS'
 foreach($name in @('MspNewBuyerDiscoveryAutoV1','MspNewBuyerBitrixAutoV2','MspDailyNewbaseSource0745V1')){
  $task=$folder.GetTask($name)
  Need ($task.Enabled -and $task.Definition.Triggers.Count -eq 1 -and $task.Definition.Triggers.Item(1).Enabled) 'SOURCE_TASK_CHANGED'
 }
 $crm=$folder.GetTask('MspDailyNewbaseCrmAutoV1')
 Need (-not $crm.Definition.Triggers.Item(1).Enabled) 'DAILY_CRM_UNEXPECTEDLY_ENABLED'
 $phase='FETCH_PINNED_WORKER'
 [void][IO.Directory]::CreateDirectory($dir)
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/500f82f2d43388f0f64b751add914fea5a37d99e/integrations/msp-bitrix24-bridge/bin/probe-newbase-customer-orders-metadata-readonly-v1.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --connect-timeout 10 --max-time 60 --output $worker $url
 Need ($LASTEXITCODE -eq 0 -and [IO.File]::Exists($worker)) 'DOWNLOAD_FAILED'
 Need ((GitBlob $worker) -eq '81fe0f47d39c3612a855e553d63227f51316a891') 'WORKER_HASH_INVALID'
 $errs=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::UTF8),[ref]$errs)
 Need ($null -eq $errs -or $errs.Count -eq 0) 'WORKER_PARSE_INVALID'
 'WORKER_HASH=PASS;PS2_PARSE=PASS'
 $phase='REGISTER_ONE_SHOT'
 $svc=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$s.NewTask(0)
 $def.RegistrationInfo.Description='READONLY metadata survey: 1C TEST NewBase customer order fields and tabular parts, once, no triggers'
 $def.Principal.UserId=$svc;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT5M'
 $def.Settings.MultipleInstances=2
 $act=$def.Actions.Create(0)
 $act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$svc,$null,5,$null)
 $task=$folder.GetTask($taskName)
 Need ($task.Definition.Triggers.Count -eq 0 -and $task.Enabled) 'TRIGGERS_NOT_ZERO'
 Need ([int]$task.Definition.Principal.LogonType -eq 5) 'NOT_SERVICE_LOGON'
 $phase='START_ONCE'
 $null=$task.Run($null)
 'TASK=STARTED;TRIGGERS=0;IDENTITY=LOCAL_SERVICE'
 'RECEIPT_PATH='+$state
 'ONEC_REQUESTS=METADATA_GET_ONLY;ONEC_WRITES=0;CRM_REQUESTS=0;SQLITE_WRITES=0'
 'RESULT=STARTED;STAGE=ONEC_CUSTOMER_ORDER_METADATA_READONLY_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^ONEC_ORDER_LAUNCH_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=ONEC_CUSTOMER_ORDER_METADATA_READONLY_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

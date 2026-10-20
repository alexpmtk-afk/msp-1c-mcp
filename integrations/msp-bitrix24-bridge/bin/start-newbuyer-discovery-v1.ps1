#requires -version 2
# Guarded one-time setup of repeatable, MANUAL-ONLY local NewBase new-buyer discovery.
# No scheduled trigger and no Bitrix writes. Administrator launches LocalService task once.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop';$phase='PRECHECK'
function Gate([string]$Code){throw ('NEWBUYER_LAUNCH_'+$Code)}
function Hash([string]$Path){$h=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){Gate 'HOST_INVALID'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Gate 'PS2_X64_REQUIRED'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Gate 'ADMIN_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $status=Join-Path $root 'state\msp-newbuyer-discovery-v1.status'
 $cfg=Join-Path $root 'config\collector.ini'
 foreach($f in @($exe,$db,$cfg,(Join-Path $root 'bin\curl.exe'),(Join-Path $root 'config\curl-ca-bundle.crt'),(Join-Path $root 'secrets\onec-test-odata.dpapi'))){
  if(-not [IO.File]::Exists($f)){Gate 'COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Gate 'REPARSE_DENIED'}
 }
 $flags=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
 foreach($f in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  if($flags -notmatch ('(?m)^'+[regex]::Escape($f)+'\s*$')){Gate 'NOT_SAFE_IDLE'}
 }
 $map=& $exe -readonly -batch -bail $db "SELECT count(*)||':'||count(DISTINCT onec_guid)||':'||(SELECT count(*) FROM (SELECT entity_kind,crm_id FROM msp_initial_map GROUP BY entity_kind,crm_id))||':'||coalesce(sum(CASE WHEN entity_kind NOT IN (3,4) OR entity_kind IS NULL OR crm_id IS NULL OR crm_id<1 THEN 1 ELSE 0 END),0) FROM msp_initial_map;"
 if($LASTEXITCODE -ne 0 -or [string]$map -ne '6433:6433:6433:0'){Gate 'MAPPING_GATE_FAILED'}
 $integrity=& $exe -readonly -batch -bail $db 'PRAGMA quick_check;'
 if($LASTEXITCODE -ne 0 -or [string]$integrity -ne 'ok'){Gate 'SQLITE_INTEGRITY'}
 $sched=New-Object -ComObject Schedule.Service;$sched.Connect();$folder=$sched.GetFolder('\')
 $name='MspNewBuyerDiscoveryV1'
 $existing=$null;try{$existing=$folder.GetTask($name)}catch{}
 if($null -ne $existing){Gate 'TASK_ALREADY_PRESENT'}
 if([IO.File]::Exists($status)){Gate 'DISCOVERY_ALREADY_ATTEMPTED'}
 foreach($t in @($folder.GetTasks(0))){
  if($t.Name -match '^Msp(CustomerStore|Newbase|NewBase|BitrixPhone|BitrixUnnamed|BitrixName|BitrixTypeReview)' -and [int]$t.State -eq 4){Gate 'RELATED_TASK_RUNNING'}
 }
 $phase='DOWNLOAD'
 $dir=Join-Path $root 'staging\msp-newbuyer-discovery-v1'
 if([IO.Directory]::Exists($dir)){Gate 'STAGING_EXISTS'}
 [void][IO.Directory]::CreateDirectory($dir)
 $worker=Join-Path $dir 'discover-newbase-new-buyers-v1.ps1'
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/a9d6c6c1ce737af81cb47438db03cd29aa6d028f/integrations/msp-bitrix24-bridge/bin/discover-newbase-new-buyers-v1.ps1'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker $url
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($worker)){Gate 'DOWNLOAD_FAILED'}
 if((Hash $worker) -ne '6630af6daec00430d7587f51f26c5960f15dcc25aaf313ffc208cbfa7c13130f'){Gate 'WORKER_HASH_MISMATCH'}
 if(([IO.File]::GetAttributes($worker) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Gate 'WORKER_REPARSE_DENIED'}
 $err=$null;$null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::UTF8),[ref]$err)
 if($err -and $err.Count -gt 0){Gate 'PS2_PARSE_FAILED'}
 'NEWBUYER_WORKER_HASH=PASS'
 $phase='REGISTER'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sched.NewTask(0)
 $def.RegistrationInfo.Description='Manual-only TEST NewBase read-only GUID scan: stage new buyers into SRV SQLite, no Bitrix writes.'
 $def.Principal.UserId=$service;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT90M';$def.Settings.MultipleInstances=2
 $act=$def.Actions.Create(0);$act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($name,$def,2,$service,$null,5,$null)
 $task=$folder.GetTask($name)
 if($null -eq $task -or $task.Definition.Triggers.Count -ne 0){Gate 'TRIGGER_NOT_EMPTY'}
 $phase='START';$null=$task.Run($null)
 'NEWBUYER_TASK=STARTED'
 'STATUS_FILE='+$status
 'SOURCE=TEST_NEWBASE';'ONEC_WRITES=0';'CRM_WRITES=0';'AUTO_UPDATE=OFF'
 'RESULT=STARTED;STAGE=MSP_NEWBUYER_DISCOVERY_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBUYER_LAUNCH_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_NEWBUYER_DISCOVERY_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}
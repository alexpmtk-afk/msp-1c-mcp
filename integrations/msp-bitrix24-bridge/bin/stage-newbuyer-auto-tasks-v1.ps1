#requires -version 2
# Stages TWO disabled schedules only. No task is run, no source/CRM/database write.
# Source: TEST NewBase, pinned previously proven V2 workers, LOCAL SERVICE.
# Future activation requires a separately reviewed opt-in; this installer NEVER activates.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK';$root='C:\ProgramData\MspCustomerStore'
function Fail([string]$Code){throw ('NEWBUYER_STAGE_'+$Code)}
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function Sha256([string]$Path){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
function GitBlob([string]$Path){
 $body=[IO.File]::ReadAllBytes($Path)
 $head=[Text.Encoding]::ASCII.GetBytes(('blob '+$body.Length+[char]0))
 $inputBytes=New-Object byte[] ($head.Length+$body.Length)
 [Array]::Copy($head,0,$inputBytes,0,$head.Length)
 [Array]::Copy($body,0,$inputBytes,$head.Length,$body.Length)
 $h=New-Object Security.Cryptography.SHA1Managed
 try{return ([BitConverter]::ToString($h.ComputeHash($inputBytes))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
function ReadDb([string]$Sql){
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $result=@(& $exe -readonly -batch -bail $db $Sql 2>&1)
 Need ($LASTEXITCODE -eq 0 -and $result.Count -eq 1) 'SQLITE_READ'
 return $result[0].ToString().Trim()
}
function VerifyFile([string]$Path){
 Need ([IO.File]::Exists($Path)) 'FILE_MISSING'
 Need (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
}
function Schedule([object]$Folder,[object]$Service,[string]$Name,[string]$Script,[string]$Every,[string]$Description,[string]$Account,[string]$Limit){
 $definition=$Service.NewTask(0)
 $definition.RegistrationInfo.Description=$Description
 $definition.Principal.UserId=$Account;$definition.Principal.LogonType=5;$definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true
 $definition.Settings.StartWhenAvailable=$false
 $definition.Settings.ExecutionTimeLimit=$Limit
 $definition.Settings.MultipleInstances=2
 $trigger=$definition.Triggers.Create(2)
 $trigger.DaysInterval=1
 $trigger.StartBoundary=[DateTime]::Now.AddHours(1).ToString('yyyy-MM-ddTHH:mm:ss')
 $trigger.Repetition.Interval=$Every
 $trigger.Repetition.Duration='P1D'
 $trigger.Enabled=$false
 $action=$definition.Actions.Create(0)
 $action.Path=Join-Path $PSHOME 'powershell.exe'
 $args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Script+'" -ExpectedComputerName SRV'
 if($Name -eq 'MspNewBuyerBitrixAutoV2'){$args+=' -Apply'}
 $action.Arguments=$args
 $null=$Folder.RegisterTaskDefinition($Name,$definition,2,$Account,$null,5,$null)
 $saved=$Folder.GetTask($Name)
 Need ($saved.Enabled -and $saved.Definition.Triggers.Count -eq 1 -and -not $saved.Definition.Triggers.Item(1).Enabled) 'TASK_ACTIVE_UNEXPECTEDLY'
 Need ([int]$saved.Definition.Principal.LogonType -eq 5) 'TASK_LOGONTYPE_WRONG'
 Need ([int]$saved.Definition.Actions.Count -eq 1) 'TASK_ACTION_COUNT'
 Need ([string]$saved.Definition.Actions.Item(1).Arguments -eq $args) 'TASK_ACTION_DIFFERENT'
 return $saved
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 $who=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 Need ($who.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'ADMIN_REQUIRED'
 $discovery=Join-Path $root 'staging\msp-newbuyer-discovery-v2-fixed\discover-newbase-new-buyers-v2.ps1'
 $delivery=Join-Path $root 'staging\newbuyer-bitrix-auto-v2\sync-newbuyer-queue-to-bitrix-auto-v2.ps1'
 foreach($file in @($discovery,$delivery,(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'data\customers.db'),(Join-Path $root 'config\collector.ini'))){VerifyFile $file}
 Need ((Sha256 $discovery) -eq '593114f7fd322e5b92030bbedae66bd125016dbd8931fce4b2a314680b5313eb') 'SOURCE_HASH_INVALID'
 Need ((GitBlob $delivery) -eq '34cbc1b815aa459fc411dedca74430d4eeb319db') 'SENDER_HASH_INVALID'
 $parse=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($delivery,[Text.Encoding]::UTF8),[ref]$parse)
 Need ($null -eq $parse -or $parse.Count -eq 0) 'SENDER_PS2_PARSE'
 $config=[IO.File]::ReadAllText((Join-Path $root 'config\collector.ini'))
 foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){Need ($config -match ('(?m)^'+[regex]::Escape($flag)+'\r?$')) 'OTHER_AUTO_FLAGS_CHANGED'}
 Need (-not [IO.File]::Exists((Join-Path $root 'config\newbuyer-crm-auto-approval.txt'))) 'APPROVAL_ALREADY_PRESENT'
 VerifyFile (Join-Path $root 'state\msp-newbuyer-discovery-v2.status')
 VerifyFile (Join-Path $root 'state\msp-newbuyer-bitrix-once-v1.status')
 $scanStatus=[IO.File]::ReadAllText((Join-Path $root 'state\msp-newbuyer-discovery-v2.status'))
 $transferStatus=[IO.File]::ReadAllText((Join-Path $root 'state\msp-newbuyer-bitrix-once-v1.status'))
 Need ($scanStatus -match 'STATUS=PASS;SOURCE=TEST_NEWBASE;ROWS=6434;QUEUE=1:1:0:0:0') 'SCAN_PROOF_MISSING'
 Need ($transferStatus -match 'STATUS=PASS;MODE=APPLY;POST_ATTEMPTS=2;ONEC_WRITES=0') 'PILOT_PROOF_MISSING'
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'DB_INTEGRITY'
 Need ((ReadDb "SELECT count(*)||':'||sum(state='DONE')||':'||sum(state='PENDING')||':'||sum(state='INTENT')||':'||sum(state='UNCERTAIN') FROM msp_newbuyer_queue;") -eq '1:1:0:0:0') 'QUEUE_NOT_IDLE'
 Need ((ReadDb "SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;") -eq '6434') 'BUYER_COUNT_CHANGED'
 $scheduler=New-Object -ComObject Schedule.Service;$scheduler.Connect();$folder=$scheduler.GetFolder('\')
 foreach($name in @('MspNewBuyerDiscoveryAutoV1','MspNewBuyerBitrixAutoV2')){
  $existing=$null;try{$existing=$folder.GetTask($name)}catch{}
  Need ($null -eq $existing) 'AUTO_TASK_ALREADY_EXISTS'
 }
 foreach($name in @('MspNewBuyerDiscoveryV2','MspNewBuyerBitrixPilotV1')){
  $task=$folder.GetTask($name)
  Need ([int]$task.State -eq 3 -and [int]$task.LastTaskResult -eq 0 -and $task.Definition.Triggers.Count -eq 0) 'BASE_TASK_NOT_ACCEPTED'
 }
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $phase='REGISTER_DISABLED'
 $null=Schedule $folder $scheduler 'MspNewBuyerDiscoveryAutoV1' $discovery 'PT30M' 'TEST NewBase: full scan for new buyers every 30 minutes (currently disabled)' $account 'PT12M'
 $null=Schedule $folder $scheduler 'MspNewBuyerBitrixAutoV2' $delivery 'PT5M' 'New buyers only: transfer one pending SQLite buyer to Bitrix24 every 5 minutes (currently disabled)' $account 'PT3M'
 $phase='CONFIRM_DISABLED'
 foreach($name in @('MspNewBuyerDiscoveryAutoV1','MspNewBuyerBitrixAutoV2')){
  $task=$folder.GetTask($name)
  Need ([int]$task.State -eq 3 -and -not $task.Definition.Triggers.Item(1).Enabled) 'TASK_NOT_DISABLED'
 }
 'STAGING=PASS'
 'SOURCE_SCHEDULE=PT30M;ENABLED=NO'
 'CRM_SCHEDULE=PT5M;ENABLED=NO'
 'EXECUTION=LOCAL_SERVICE'
 'SOURCE=TEST_NEWBASE'
 'ONEC_WRITES=0'
 'CRM_WRITES=0'
 'AUTO_UPDATE=OFF'
 'RESULT=PASS;STAGE=MSP_NEWBUYER_AUTO_TASKS_PAUSED_V1'
}catch{
 $gate='RUNTIME_ERROR';if($_.Exception.Message -match '^NEWBUYER_STAGE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_NEWBUYER_AUTO_TASKS_PAUSED_V1;PHASE='+$phase+';GATE='+$gate
 'AUTO_ACTIVATION=NOT_AUTHORIZED'
 exit 1
}
#requires -version 2
# Explicit opt-in: activate ONLY TEST NewBase new-buyer discovery (30m) and CRM delivery (5m).
# Never enables prior full-base autosync. Existing 6433 CRM buyers remain untouched.
# Fail closed, pause BOTH tasks and remove this script's approval on failure.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$phase='PRECHECK';$approval=Join-Path $root 'config\newbuyer-crm-auto-approval.txt'
$sourceTask='MspNewBuyerDiscoveryAutoV1';$crmTask='MspNewBuyerBitrixAutoV2'
$source=Join-Path $root 'staging\msp-newbuyer-discovery-v2-fixed\discover-newbase-new-buyers-v2.ps1'
$sender=Join-Path $root 'staging\newbuyer-bitrix-auto-v2\sync-newbuyer-queue-to-bitrix-auto-v2.ps1'
$scheduler=$null;$folder=$null;$createdApproval=$false;$changed=$false
function Fail([string]$Code){throw ('ACTIVATE_'+$Code)}
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function Digest([string]$File){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($File)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
function Blob([string]$File){
 $b=[IO.File]::ReadAllBytes($File)
 $head=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
 $combined=New-Object byte[] ($head.Length+$b.Length)
 [Array]::Copy($head,0,$combined,0,$head.Length)
 [Array]::Copy($b,0,$combined,$head.Length,$b.Length)
 $alg=New-Object Security.Cryptography.SHA1Managed
 try{return ([BitConverter]::ToString($alg.ComputeHash($combined))).Replace('-','').ToLowerInvariant()}
 finally{$alg.Clear()}
}
function ReadDb([string]$Sql){
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $out=@(& $exe -readonly -batch -bail $db $Sql 2>&1)
 Need ($LASTEXITCODE -eq 0 -and $out.Count -eq 1) 'LOCAL_DB_READ_FAILED'
 return $out[0].ToString().Trim()
}
function CheckTask([string]$Name,[string]$Script,[string]$Every,[string]$ExpectedArg,[string]$ExpectedSid){
 $t=$folder.GetTask($Name);$def=$t.Definition
 Need ($t.Enabled -and [int]$t.State -eq 3) 'TASK_STATE_CHANGED'
 Need ($def.Triggers.Count -eq 1 -and [int]$def.Triggers.Item(1).Type -eq 2) 'TRIGGER_SHAPE'
 Need (-not $def.Triggers.Item(1).Enabled -and $def.Triggers.Item(1).Repetition.Interval -eq $Every) 'TRIGGER_CHANGED'
 Need ([int]$def.Principal.LogonType -eq 5) 'LOGON_TYPE_CHANGED'
 $sid=([Security.Principal.NTAccount]$def.Principal.UserId).Translate([Security.Principal.SecurityIdentifier]).Value
 Need ($sid -eq $ExpectedSid) 'SERVICE_IDENTITY_CHANGED'
 Need ($def.Actions.Count -eq 1) 'ACTION_COUNT_CHANGED'
 Need ([string]$def.Actions.Item(1).Path -eq (Join-Path $PSHOME 'powershell.exe')) 'ACTION_PATH_CHANGED'
 Need ([string]$def.Actions.Item(1).Arguments -eq $ExpectedArg) 'ACTION_ARGUMENTS_CHANGED'
 Need ($def.Actions.Item(1).Arguments -match [regex]::Escape($Script)) 'SCRIPT_CHANGED'
 return $t
}
function Disable([string]$Name){
 $task=$folder.GetTask($Name);$definition=$task.Definition
 if($definition.Triggers.Count -ne 1){return}
 if($definition.Triggers.Item(1).Enabled){
  $definition.Triggers.Item(1).Enabled=$false
  $id=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $null=$folder.RegisterTaskDefinition($Name,$definition,4,$id,$null,5,$null)
 }
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'HOST_INVALID'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 $who=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 Need ($who.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'ADMIN_REQUIRED'
 foreach($f in @($source,$sender,(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'data\customers.db'),(Join-Path $root 'config\collector.ini'))){
  Need ([IO.File]::Exists($f)) 'COMPONENT_MISSING'
  Need (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 }
 Need ((Digest $source) -eq '593114f7fd322e5b92030bbedae66bd125016dbd8931fce4b2a314680b5313eb') 'SOURCE_HASH_INVALID'
 Need ((Blob $sender) -eq '34cbc1b815aa459fc411dedca74430d4eeb319db') 'SENDER_HASH_INVALID'
 $config=[IO.File]::ReadAllText((Join-Path $root 'config\collector.ini'))
 foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){Need ($config -match ('(?m)^'+[regex]::Escape($flag)+'\r?$')) 'LEGACY_AUTOMATION_FLAGS_CHANGED'}
 Need (-not [IO.File]::Exists($approval)) 'ALREADY_APPROVED_OR_ACTIVATED'
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_INTEGRITY_FAILED'
 Need ((ReadDb 'SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;') -eq '6434') 'BUYER_COUNTS_CHANGED'
 Need ((ReadDb "SELECT count(*)||':'||coalesce(sum(state='DONE'),0)||':'||coalesce(sum(state='PENDING'),0)||':'||coalesce(sum(state='INTENT'),0)||':'||coalesce(sum(state='UNCERTAIN'),0) FROM msp_newbuyer_queue;") -eq '1:1:0:0:0') 'QUEUE_NOT_IDLE'
 $scheduler=New-Object -ComObject Schedule.Service;$scheduler.Connect();$folder=$scheduler.GetFolder('\')
 $sid='S-1-5-19'
 $sourceArgs='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$source+'" -ExpectedComputerName SRV'
 $senderArgs='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$sender+'" -ExpectedComputerName SRV -Apply'
 $null=CheckTask $sourceTask $source 'PT30M' $sourceArgs $sid
 $null=CheckTask $crmTask $sender 'PT5M' $senderArgs $sid
 $phase='CREATE_EXPLICIT_APPROVAL'
 [IO.File]::WriteAllText($approval,'ALLOW_NEW_BUYERS=YES;SOURCE=TEST_NEWBASE;MAX_PER_RUN=1',[Text.Encoding]::ASCII)
 $createdApproval=$true
 Need ([IO.File]::ReadAllText($approval,[Text.Encoding]::ASCII).Trim() -eq 'ALLOW_NEW_BUYERS=YES;SOURCE=TEST_NEWBASE;MAX_PER_RUN=1') 'APPROVAL_BACKREAD_INVALID'
 $phase='ENABLE_TEST_NEWBUYER_TASKS'
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $task=$folder.GetTask($sourceTask);$definition=$task.Definition
 $definition.Triggers.Item(1).StartBoundary=[DateTime]::Now.AddMinutes(2).ToString('yyyy-MM-ddTHH:mm:ss')
 $definition.Triggers.Item(1).Enabled=$true
 $changed=$true;$null=$folder.RegisterTaskDefinition($sourceTask,$definition,4,$account,$null,5,$null)
 $task=$folder.GetTask($crmTask);$definition=$task.Definition
 $definition.Triggers.Item(1).StartBoundary=[DateTime]::Now.AddMinutes(5).ToString('yyyy-MM-ddTHH:mm:ss')
 $definition.Triggers.Item(1).Enabled=$true
 $null=$folder.RegisterTaskDefinition($crmTask,$definition,4,$account,$null,5,$null)
 $phase='VERIFY_ACTIVATION'
 foreach($n in @($sourceTask,$crmTask)){
  $task=$folder.GetTask($n)
  Need ($task.Enabled -and $task.Definition.Triggers.Count -eq 1 -and $task.Definition.Triggers.Item(1).Enabled) 'AUTO_TRIGGER_NOT_ENABLED'
 }
 'NEWBUYER_AUTO_ACTIVATION=PASS'
 'SOURCE_SCAN_INTERVAL=PT30M'
 'CRM_QUEUE_INTERVAL=PT5M'
 'SOURCE_TASK=ENABLED'
 'CRM_TASK=ENABLED'
 'SOURCE=TEST_NEWBASE'
 'LEGACY_AUTO=OFF'
 'ONEC_WRITES=0'
 'INITIAL_QUEUE_PENDING=0'
 'RESULT=PASS;STAGE=MSP_NEWBUYER_AUTO_ACTIVATION_V1'
}catch{
 $reason=$_.Exception
 $gate='RUNTIME_ERROR';if($reason.Message -match '^ACTIVATE_([A-Z0-9_]+)){$gate=$Matches[1]}
 $hr='UNKNOWN';try{$hr=('{0:X8}' -f ($reason.HResult -band 0xffffffff))}catch{}
 $errType=$reason.GetType().Name
 $rollbackSource='NOT_NEEDED';$rollbackCrm='NOT_NEEDED'
 if($changed -and $null -ne $folder){
  $rollbackSource='FAIL';try{Disable $sourceTask;$rollbackSource='PASS'}catch{}
  $rollbackCrm='FAIL';try{Disable $crmTask;$rollbackCrm='PASS'}catch{}
 }
 if($createdApproval){try{[IO.File]::Delete($approval)}catch{}}
 $approvalState='UNKNOWN';try{$approvalState=if([IO.File]::Exists($approval)){'PRESENT'}else{'ABSENT'}}catch{}
 'RESULT=FAIL;STAGE=MSP_NEWBUYER_AUTO_ACTIVATION_V1;PHASE='+$phase+';GATE='+$gate
 'EXCEPTION_TYPE='+$errType+';HRESULT='+$hr
 'ROLLBACK_SOURCE='+$rollbackSource+';ROLLBACK_CRM='+$rollbackCrm+';APPROVAL='+$approvalState
 'CHECK_BOTH_TRIGGERS_BEFORE_RETRY=YES'
 exit 1
}
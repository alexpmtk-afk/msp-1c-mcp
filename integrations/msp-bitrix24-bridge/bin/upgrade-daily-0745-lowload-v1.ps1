#requires -version 2
# Upgrade ONLY two PAUSED daily scheduler tasks: OData pacing and 08:00-14:00 CRM window.
# No PowerShell execution of daily workers. No OData, 1C, Bitrix, or SQLite calls.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$phase='PRECHECK'
$oldSourceDef=$null;$oldCrmDef=$null;$changedSource=$false;$changedCrm=$false;$folder=$null
function Fail([string]$Code){throw ('DAILY_TUNE_'+$Code)}
function Need([bool]$Condition,[string]$Code){if(-not $Condition){Fail $Code}}
function Blob([string]$Path){
 Need ([IO.File]::Exists($Path)) 'PINNED_FILE_MISSING'
 Need (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 $data=[IO.File]::ReadAllBytes($Path)
 $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length+[char]0))
 $combined=New-Object byte[] ($header.Length+$data.Length)
 [Array]::Copy($header,0,$combined,0,$header.Length)
 [Array]::Copy($data,0,$combined,$header.Length,$data.Length)
 $h=New-Object Security.Cryptography.SHA1Managed
 try{return ([BitConverter]::ToString($h.ComputeHash($combined))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
function CheckTask([object]$T,[string]$OldPath,[string]$Sid){
 Need ($T.Enabled -and $T.Definition.Triggers.Count -eq 1) 'TASK_NOT_REGISTERED'
 $trigger=$T.Definition.Triggers.Item(1)
 Need (-not $trigger.Enabled -and [int]$trigger.Type -eq 2) 'TASK_NOT_PAUSED'
 Need ($T.Definition.Actions.Count -eq 1) 'ACTION_COUNT'
 Need ($T.Definition.Actions.Item(1).Path -eq (Join-Path $PSHOME 'powershell.exe')) 'ACTION_EXE_MISMATCH'
 Need ([string]$T.Definition.Actions.Item(1).Arguments -match [regex]::Escape($OldPath)) 'ACTION_SCRIPT_MISMATCH'
 Need ([string]$T.Definition.Actions.Item(1).Arguments -match ' -Apply$') 'ACTION_APPLY_MISSING'
 $user=[string]$T.Definition.Principal.UserId
 Need (([Security.Principal.NTAccount]$user).Translate([Security.Principal.SecurityIdentifier]).Value -eq $Sid) 'NOT_LOCAL_SERVICE'
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 $p=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 Need ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'ADMIN_REQUIRED'
 $old=Join-Path $root 'staging\daily-newbase-0745-v1\daily-reconcile-newbase-buyers-v1.ps1'
 $new=Join-Path $root 'staging\daily-newbase-0745-v2\daily-reconcile-newbase-buyers-v1.ps1'
 $worker=Join-Path $root 'staging\daily-newbase-0745-v1\daily-sync-existing-to-bitrix-v1.ps1'
 Need ((Blob $old) -eq 'd67c0b7cdc44fa94795ff6bb0283cab8f7a185fc') 'ORIGINAL_SOURCE_CHANGED'
 Need ((Blob $new) -eq '812504af7a69ed13ddc44546ea2c51eb043476e8') 'LOWLOAD_SOURCE_HASH_INVALID'
 Need ((Blob $worker) -eq '9a2bf91dfd0b18bf7f4a917dc3583a6f347d4cb4') 'CRM_WORKER_CHANGED'
 $parse=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($new,[Text.Encoding]::UTF8),[ref]$parse)
 Need ($null -eq $parse -or $parse.Count -eq 0) 'PS2_PARSE'
 $sched=New-Object -ComObject Schedule.Service
 $sched.Connect();$folder=$sched.GetFolder('\')
 $sourceName='MspDailyNewbaseSource0745V1';$crmName='MspDailyNewbaseCrmAutoV1'
 $src=$folder.GetTask($sourceName);$crm=$folder.GetTask($crmName)
 $sid='S-1-5-19'
 CheckTask $src $old $sid
 CheckTask $crm $worker $sid
 Need ($src.Definition.Triggers.Item(1).StartBoundary -match 'T07:45:00$') 'SOURCE_NOT_0745'
 Need ($crm.Definition.Triggers.Item(1).StartBoundary -match 'T08:00:00$') 'CRM_NOT_0800'
 Need ($crm.Definition.Triggers.Item(1).Repetition.Interval -eq 'PT5M') 'CRM_INTERVAL_CHANGED'
 Need ($crm.Definition.Triggers.Item(1).Repetition.Duration -eq 'P1D') 'CRM_OLD_WINDOW_CHANGED'
 $preview=$null
 try{$preview=$folder.GetTask('MspDailyNewbasePreviewOnceV1')}catch{}
 if($null -ne $preview){Need ([int]$preview.State -ne 4) 'PREVIEW_CURRENTLY_RUNNING'}
 $oldSourceDef=$src.Definition
 $oldCrmDef=$crm.Definition
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList $sid).Translate([Security.Principal.NTAccount]).Value
 $phase='UPDATE_PAUSED_SOURCE'
 $newSourceDef=$folder.GetTask($sourceName).Definition
 $args=[string]$newSourceDef.Actions.Item(1).Arguments
 Need ($args.IndexOf($old) -ge 0) 'SOURCE_ACTION_PATH_ABSENT'
 $newSourceDef.Actions.Item(1).Arguments=$args.Replace($old,$new)
 $null=$folder.RegisterTaskDefinition($sourceName,$newSourceDef,4,$account,$null,5,$null)
 $changedSource=$true
 $phase='SHORTEN_PAUSED_CRM_WINDOW'
 $newCrmDef=$folder.GetTask($crmName).Definition
 $newCrmDef.Triggers.Item(1).Repetition.Duration='PT6H'
 $null=$folder.RegisterTaskDefinition($crmName,$newCrmDef,4,$account,$null,5,$null)
 $changedCrm=$true
 $phase='VERIFY'
 $src=$folder.GetTask($sourceName);$crm=$folder.GetTask($crmName)
 CheckTask $src $new $sid
 CheckTask $crm $worker $sid
 Need ($src.Definition.Triggers.Item(1).StartBoundary -match 'T07:45:00$') 'SOURCE_SCHEDULE_CHANGED'
 Need ($crm.Definition.Triggers.Item(1).Repetition.Duration -eq 'PT6H') 'CRM_WINDOW_NOT_SHORTENED'
 'TUNING=PASS'
 'SOURCE_TIME=07:45;ENABLED=NO;PAGES=100;PAUSE_MS=750;MAX_RETRY=0'
 'CRM_TIME=08:00-14:00;INTERVAL=PT5M;ENABLED=NO'
 'DAYTIME_AUTO=UNCHANGED'
 'ONEC_WRITES=0';'CRM_WRITES=0';'SQLITE_WRITES=0';'ODATA_REQUESTS=0'
 'RESULT=PASS;STAGE=MSP_DAILY_0745_LOWLOAD_PAUSED_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^DAILY_TUNE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($null -ne $folder){
  $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  if($changedSource -and $null -ne $oldSourceDef){try{$null=$folder.RegisterTaskDefinition('MspDailyNewbaseSource0745V1',$oldSourceDef,4,$account,$null,5,$null)}catch{}}
  if($changedCrm -and $null -ne $oldCrmDef){try{$null=$folder.RegisterTaskDefinition('MspDailyNewbaseCrmAutoV1',$oldCrmDef,4,$account,$null,5,$null)}catch{}}
 }
 'RESULT=FAIL;STAGE=MSP_DAILY_0745_LOWLOAD_PAUSED_V1;PHASE='+$phase+';GATE='+$gate
 'AUTO_ENABLED=NO'
 exit 1
}

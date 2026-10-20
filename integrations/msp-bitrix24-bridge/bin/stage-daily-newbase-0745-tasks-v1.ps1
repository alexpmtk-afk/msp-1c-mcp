#requires -version 2
# Stage ONLY two disabled tasks; not a single CRM, 1C or SQLite mutation.
# Does not touch existing MspNewBuyerDiscoveryAutoV1 / MspNewBuyerBitrixAutoV2 tasks.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$phase='PRECHECK';$created=New-Object Collections.ArrayList
function Fail([string]$Code){throw ('DAILY_STAGE_'+$Code)}
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function VerifyFile([string]$Path){
 Need ([IO.File]::Exists($Path)) 'FILE_NOT_PRESENT'
 Need (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
}
function GitBlob([string]$Path){
 $body=[IO.File]::ReadAllBytes($Path)
 $prefix=[Text.Encoding]::ASCII.GetBytes(('blob '+$body.Length+[char]0))
 $bytes=New-Object byte[] ($prefix.Length+$body.Length)
 [Array]::Copy($prefix,0,$bytes,0,$prefix.Length)
 [Array]::Copy($body,0,$bytes,$prefix.Length,$body.Length)
 $alg=New-Object Security.Cryptography.SHA1Managed
 try{return ([BitConverter]::ToString($alg.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
 finally{$alg.Clear()}
}
function ParseFile([string]$Path){
 $errs=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8),[ref]$errs)
 Need ($null -eq $errs -or $errs.Count -eq 0) 'PS2_PARSE_INVALID'
}
function ReadDb([string]$Sql){
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $result=@(& $exe -readonly -batch -bail $db $Sql 2>&1)
 Need ($LASTEXITCODE -eq 0 -and $result.Count -eq 1) 'SQLITE_READ_FAILED'
 return $result[0].ToString().Trim()
}
function RegisterPaused([object]$S,[object]$Folder,[string]$Name,[string]$Script,[DateTime]$Time,[string]$Interval,[string]$Account,[string]$Description,[string]$Max){
 $def=$S.NewTask(0)
 $def.RegistrationInfo.Description=$Description
 $def.Principal.UserId=$Account
 $def.Principal.LogonType=5
 $def.Principal.RunLevel=0
 $def.Settings.Enabled=$true
 $def.Settings.StartWhenAvailable=$false
 $def.Settings.ExecutionTimeLimit=$Max
 $def.Settings.MultipleInstances=2
 $tr=$def.Triggers.Create(2)
 $tr.DaysInterval=1
 $tr.StartBoundary=$Time.ToString('yyyy-MM-ddTHH:mm:ss')
 $tr.Enabled=$false
 if($Interval -ne ''){
  $tr.Repetition.Interval=$Interval
  $tr.Repetition.Duration='P1D'
 }
 $act=$def.Actions.Create(0)
 $act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Script+'" -ExpectedComputerName SRV -Apply'
 $null=$Folder.RegisterTaskDefinition($Name,$def,2,$Account,$null,5,$null)
 [void]$created.Add($Name)
 $check=$Folder.GetTask($Name)
 Need ($check.Enabled -and $check.Definition.Triggers.Count -eq 1 -and -not $check.Definition.Triggers.Item(1).Enabled) 'TRIGGER_NOT_PAUSED'
 Need ([int]$check.Definition.Principal.LogonType -eq 5) 'WRONG_LOGON'
 Need ($check.Definition.Actions.Count -eq 1 -and [string]$check.Definition.Actions.Item(1).Arguments -eq $act.Arguments) 'ACTION_NOT_VERIFIED'
 return $check
}
try{
 Need ($env:COMPUTERNAME -eq $ExpectedComputerName -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 $who=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 Need ($who.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'ADMIN_REQUIRED'
 $source=Join-Path $root 'staging\daily-newbase-0745-v1\daily-reconcile-newbase-buyers-v1.ps1'
 $worker=Join-Path $root 'staging\daily-newbase-0745-v1\daily-sync-existing-to-bitrix-v1.ps1'
 foreach($f in @($source,$worker,(Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'data\customers.db'),(Join-Path $root 'config\collector.ini'))){VerifyFile $f}
 Need ((GitBlob $source) -eq 'd67c0b7cdc44fa94795ff6bb0283cab8f7a185fc') 'SOURCE_HASH_MISMATCH'
 Need ((GitBlob $worker) -eq '9a2bf91dfd0b18bf7f4a917dc3583a6f347d4cb4') 'CRM_HASH_MISMATCH'
 ParseFile $source
 ParseFile $worker
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'DB_INTEGRITY'
 Need ((ReadDb 'SELECT count(*) FROM msp_initial_map;') -eq '6433') 'BASELINE_MAPPING_CHANGED'
 $config=[IO.File]::ReadAllText((Join-Path $root 'config\collector.ini'),[Text.Encoding]::ASCII)
 foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){Need ($config -match ('(?m)^'+[regex]::Escape($flag)+'\r?$')) 'LEGACY_FLAGS_CHANGED'}
 Need (-not [IO.File]::Exists((Join-Path $root 'config\daily-newbase-local-approval.txt'))) 'DAILY_LOCAL_ALREADY_ENABLED'
 Need (-not [IO.File]::Exists((Join-Path $root 'config\daily-newbase-crm-approval.txt'))) 'DAILY_CRM_ALREADY_ENABLED'
 $sched=New-Object -ComObject Schedule.Service
 $sched.Connect()
 $folder=$sched.GetFolder('\')
 foreach($name in @('MspDailyNewbaseSource0745V1','MspDailyNewbaseCrmAutoV1')){
  $existing=$null
  try{$existing=$folder.GetTask($name)}catch{}
  Need ($null -eq $existing) 'DAILY_TASK_ALREADY_EXISTS'
 }
 foreach($name in @('MspNewBuyerDiscoveryAutoV1','MspNewBuyerBitrixAutoV2')){
  $task=$folder.GetTask($name)
  Need ($task.Definition.Triggers.Count -eq 1 -and $task.Definition.Triggers.Item(1).Enabled -and [int]$task.LastTaskResult -eq 0) 'EXISTING_AUTO_NOT_HEALTHY'
 }
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $day=[DateTime]::Now.Date.AddDays(1)
 $phase='REGISTER_DISABLED'
 $null=RegisterPaused $sched $folder 'MspDailyNewbaseSource0745V1' $source ($day.AddHours(7).AddMinutes(45)) '' $account 'TEST NewBase: full buyer diff at 07:45 LOCAL SRV (PAUSED until separate approval)' 'PT30M'
 $null=RegisterPaused $sched $folder 'MspDailyNewbaseCrmAutoV1' $worker ($day.AddHours(8)) 'PT5M' $account 'TEST NewBase mapped changed customers: one CRM update per 5min (PAUSED until approval)' 'PT3M'
 $phase='VERIFY'
 foreach($name in @('MspDailyNewbaseSource0745V1','MspDailyNewbaseCrmAutoV1')){
  $t=$folder.GetTask($name)
  Need ([int]$t.State -eq 3 -and -not $t.Definition.Triggers.Item(1).Enabled) 'TASK_NOT_PAUSED'
 }
 'STAGING=PASS'
 'SOURCE_TIME=07:45;ENABLED=NO'
 'CRM_START=08:00;INTERVAL=PT5M;ENABLED=NO'
 'SERVER_TIMEZONE='+[TimeZoneInfo]::Local.Id
 'EXECUTION=LOCAL_SERVICE'
 'CURRENT_NEWBUYER_AUTO=UNCHANGED'
 'ONEC_WRITES=0';'CRM_WRITES=0';'SQLITE_WRITES=0'
 'RESULT=PASS;STAGE=MSP_DAILY_0745_PAUSED_V1'
}catch{
 $gate='RUNTIME_ERROR';if($_.Exception.Message -match '^DAILY_STAGE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($null -ne $folder){
  foreach($name in $created){try{$folder.DeleteTask($name,0)}catch{}}
 }
 'RESULT=FAIL;STAGE=MSP_DAILY_0745_PAUSED_V1;PHASE='+$phase+';GATE='+$gate
 'AUTO_ENABLED=NO'
 exit 1
}

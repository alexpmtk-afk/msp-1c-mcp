#requires -version 2
# Explicit opt-in: enable ONLY daily 07:45 TEST NewBase -> local SQLite reconciliation.
# Never enable CRM daily worker or change current daytime 30m/5m tasks.
# No OData, Bitrix, 1C or SQLite writes in this installer.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$phase='PRECHECK';$approval=Join-Path $root 'config\daily-newbase-local-approval.txt'
$approved=$false;$attempted=$false;$folder=$null;$oldDef=$null
function Fail([string]$Code){throw ('DAILY_SOURCE_ACTIVATE_'+$Code)}
function Need([bool]$Condition,[string]$Code){if(-not $Condition){Fail $Code}}
function VerifyFile([string]$Path){
 Need ([IO.File]::Exists($Path)) 'FILE_MISSING'
 Need (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
}
function Blob([string]$Path){
 VerifyFile $Path
 $data=[IO.File]::ReadAllBytes($Path)
 $head=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length+[char]0))
 $bytes=New-Object byte[] ($head.Length+$data.Length)
 [Array]::Copy($head,0,$bytes,0,$head.Length)
 [Array]::Copy($data,0,$bytes,$head.Length,$data.Length)
 $alg=New-Object Security.Cryptography.SHA1Managed
 try{return ([BitConverter]::ToString($alg.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
 finally{$alg.Clear()}
}
function ReadDb([string]$Sql){
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $out=@(& $exe -readonly -batch -bail $db $Sql 2>&1)
 Need ($LASTEXITCODE -eq 0 -and $out.Count -eq 1) 'SQLITE_READ_FAILED'
 return $out[0].ToString().Trim()
}
function TaskGuard([object]$Task,[string]$File,[bool]$ShouldEnable){
 Need ($Task.Enabled -and $Task.Definition.Triggers.Count -eq 1) 'TASK_MISSING_OR_DISABLED'
 $tr=$Task.Definition.Triggers.Item(1)
 Need ([int]$tr.Type -eq 2 -and $tr.Enabled -eq $ShouldEnable) 'UNEXPECTED_TRIGGER'
 Need ($Task.Definition.Actions.Count -eq 1) 'BAD_ACTION_COUNT'
 Need ($Task.Definition.Actions.Item(1).Path -eq (Join-Path $PSHOME 'powershell.exe')) 'EXECUTABLE_CHANGED'
 Need ([string]$Task.Definition.Actions.Item(1).Arguments -match [regex]::Escape($File)) 'ACTION_PATH_CHANGED'
 Need ([string]$Task.Definition.Actions.Item(1).Arguments -match ' -Apply$') 'MISSING_APPLY_SWITCH'
 Need ([int]$Task.Definition.Principal.LogonType -eq 5) 'NOT_SERVICE_LOGON'
 Need (([Security.Principal.NTAccount]([string]$Task.Definition.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-19') 'NOT_LOCAL_SERVICE'
}
try{
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ((Get-Date -Format 'zzz') -eq '+03:00') 'SRV_TIMEZONE_MISMATCH'
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 Need ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'ADMIN_REQUIRED'
 $source=Join-Path $root 'staging\daily-newbase-0745-v2\daily-reconcile-newbase-buyers-v1.ps1'
 $worker=Join-Path $root 'staging\daily-newbase-0745-v1\daily-sync-existing-to-bitrix-v1.ps1'
 Need ((Blob $source) -eq '812504af7a69ed13ddc44546ea2c51eb043476e8') 'SOURCE_HASH_CHANGED'
 Need ((Blob $worker) -eq '9a2bf91dfd0b18bf7f4a917dc3583a6f347d4cb4') 'CRM_WORKER_CHANGED'
 foreach($f in @((Join-Path $root 'bin\sqlite3.exe'),(Join-Path $root 'data\customers.db'),(Join-Path $root 'config\collector.ini'))){VerifyFile $f}
 Need ([IO.Directory]::Exists((Join-Path $root 'backups'))) 'BACKUP_FOLDER_MISSING'
 Need ([IO.Directory]::Exists((Join-Path $root 'config'))) 'CONFIG_FOLDER_MISSING'
 Need (-not [IO.File]::Exists($approval)) 'LOCAL_APPROVAL_ALREADY_EXISTS'
 Need (-not [IO.File]::Exists((Join-Path $root 'config\daily-newbase-crm-approval.txt'))) 'CRM_APPROVAL_ALREADY_EXISTS'
 Need ((ReadDb 'PRAGMA quick_check;') -eq 'ok') 'SQLITE_INTEGRITY'
 Need ((ReadDb 'SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;') -eq '6435') 'ACTIVE_BASELINE_CHANGED'
 Need ((ReadDb 'SELECT count(*) FROM msp_initial_map;') -eq '6433') 'INITIAL_MAP_CHANGED'
 Need ((ReadDb 'SELECT count(*) FROM msp_auto_map;') -eq '2') 'AUTO_MAP_CHANGED'
 Need ((ReadDb 'SELECT count(*) FROM customers c WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND NOT EXISTS(SELECT 1 FROM msp_initial_map m WHERE m.onec_guid=c.onec_guid) AND NOT EXISTS(SELECT 1 FROM msp_auto_map a WHERE a.onec_guid=c.onec_guid);') -eq '0') 'UNMAPPED_BUYERS'
 Need ((ReadDb 'SELECT count(*) FROM customers c WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND EXISTS(SELECT 1 FROM msp_initial_map m WHERE m.onec_guid=c.onec_guid) AND EXISTS(SELECT 1 FROM msp_auto_map a WHERE a.onec_guid=c.onec_guid);') -eq '0') 'DOUBLE_MAPPED'
 Need ((ReadDb "SELECT count(*) FROM msp_newbuyer_queue WHERE state IN ('INTENT','UNCERTAIN');") -eq '0') 'UNRESOLVED_NEWBUYER'
 $dailyExists=ReadDb "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='msp_daily_queue';"
 Need ($dailyExists -eq '0') 'DAILY_QUEUE_ALREADY_EXISTS'
 $config=[IO.File]::ReadAllText((Join-Path $root 'config\collector.ini'),[Text.Encoding]::ASCII)
 foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){Need ($config -match ('(?m)^'+[regex]::Escape($flag)+'\r?$')) 'LEGACY_CONFIG_CHANGED'}
 $disk=New-Object IO.DriveInfo -ArgumentList 'C'
 Need ($disk.AvailableFreeSpace -ge 536870912) 'BACKUP_DISK_SPACE_LOW'
 $s=New-Object -ComObject Schedule.Service;$s.Connect();$folder=$s.GetFolder('\')
 $name='MspDailyNewbaseSource0745V1';$crmName='MspDailyNewbaseCrmAutoV1'
 $src=$folder.GetTask($name);$crm=$folder.GetTask($crmName)
 TaskGuard $src $source $false
 TaskGuard $crm $worker $false
 Need ([int]$src.State -eq 3 -and [int]$crm.State -eq 3) 'DAILY_TASK_NOT_READY'
 Need ($src.Definition.Triggers.Item(1).StartBoundary -match 'T07:45:00$') 'SOURCE_START_TIME_CHANGED'
 Need ($crm.Definition.Triggers.Item(1).StartBoundary -match 'T08:00:00$') 'CRM_START_TIME_CHANGED'
 Need ($crm.Definition.Triggers.Item(1).Repetition.Interval -eq 'PT5M') 'CRM_INTERVAL_CHANGED'
 Need ($crm.Definition.Triggers.Item(1).Repetition.Duration -eq 'PT6H') 'CRM_WINDOW_CHANGED'
 foreach($n in @('MspNewBuyerDiscoveryAutoV1','MspNewBuyerBitrixAutoV2')){
  $t=$folder.GetTask($n)
  Need ($t.Enabled -and $t.Definition.Triggers.Count -eq 1 -and $t.Definition.Triggers.Item(1).Enabled) 'DAYTIME_AUTO_NOT_HEALTHY'
 }
 $preview=$null;try{$preview=$folder.GetTask('MspDailyNewbasePreviewOnceV1')}catch{}
 if($null -ne $preview){Need ([int]$preview.State -ne 4) 'PREVIEW_RUNNING'}
 $oldDef=$src.Definition
 $start=[DateTime]::Now.Date.AddDays(1).AddHours(7).AddMinutes(45)
 $phase='LOCAL_APPROVAL'
 $value='ALLOW_DAILY_LOCAL=YES;SOURCE=TEST_NEWBASE;MAX_REMOVED=5;MAX_NEW=20'
 [IO.File]::WriteAllText($approval,$value,[Text.Encoding]::ASCII)
 $approved=$true
 Need ([IO.File]::ReadAllText($approval,[Text.Encoding]::ASCII).Trim() -eq $value) 'LOCAL_APPROVAL_READBACK'
 $phase='ENABLE_SOURCE_ONLY'
 $definition=$folder.GetTask($name).Definition
 $definition.Triggers.Item(1).StartBoundary=$start.ToString('yyyy-MM-ddTHH:mm:ss')
 $definition.Triggers.Item(1).Enabled=$true
 $definition.Settings.StartWhenAvailable=$false
 $definition.Settings.MultipleInstances=2
 $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $attempted=$true
 $null=$folder.RegisterTaskDefinition($name,$definition,4,$account,$null,5,$null)
 $phase='VERIFY'
 $newSrc=$folder.GetTask($name);$newCrm=$folder.GetTask($crmName)
 TaskGuard $newSrc $source $true
 TaskGuard $newCrm $worker $false
 Need ($newSrc.Definition.Triggers.Item(1).StartBoundary -eq $start.ToString('yyyy-MM-ddTHH:mm:ss')) 'NEXT_DAY_NOT_VERIFIED'
 Need ((Test-Path (Join-Path $root 'config\daily-newbase-crm-approval.txt')) -eq $false) 'CRM_APPROVAL_APPEARED'
 Need ([IO.File]::ReadAllText($approval,[Text.Encoding]::ASCII).Trim() -eq $value) 'APPROVAL_CHANGED'
 'ACTIVATION=PASS'
 'SOURCE=TEST_NEWBASE;EVERY_DAY=07:45;FIRST_DATE='+$start.ToString('yyyy-MM-dd')
 'SOURCE_TRIGGER_ENABLED=YES;CRM_TRIGGER_ENABLED=NO'
 'CRM_APPROVAL=NO;CRM_WRITES=0'
 'DAYTIME_AUTO=UNCHANGED;ONEC_WRITES=0;SQLITE_WRITES=0;ODATA_REQUESTS=0'
 'RESULT=PASS;STAGE=MSP_DAILY_SOURCE_ONLY_ACTIVATION_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^DAILY_SOURCE_ACTIVATE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($attempted -and $null -ne $folder -and $null -ne $oldDef){
  try{
   $acc=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
   $null=$folder.RegisterTaskDefinition('MspDailyNewbaseSource0745V1',$oldDef,4,$acc,$null,5,$null)
  }catch{}
 }
 if($approved){try{[IO.File]::Delete($approval)}catch{}}
 'RESULT=FAIL;STAGE=MSP_DAILY_SOURCE_ONLY_ACTIVATION_V1;PHASE='+$phase+';GATE='+$gate
 'CRM_TRIGGER_ENABLED=NO'
 exit 1
}

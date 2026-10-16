#requires -version 2
# One-time machine-owned indexed Bitrix client lookup preparation.
# Only the existing customer SQLite is modified to add an FTS5 index.
# Never contacts Bitrix or 1C; leaves their existing system tasks untouched.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('BRIDGE_'+$Code)}
function Hash([string]$File){
 $sha=New-Object Security.Cryptography.SHA256Managed
 try{$digest=$sha.ComputeHash([IO.File]::ReadAllBytes($File));return ([BitConverter]::ToString($digest)).Replace('-','').ToLowerInvariant()}
 finally{$sha.Clear()}
}
function ReadSql([string]$Exe,[string]$Db,[string]$Query){
 $values=@(& $Exe -readonly -batch -bail $Db $Query 2>&1)
 if($LASTEXITCODE -ne 0){Fail 'SQLITE_READONLY_CHECK_FAILED'}
 return ($values -join '').Trim()
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $id
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $legacy='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
 $config=Join-Path $root 'config\collector.ini'
 $exe=Join-Path $root 'bin\sqlite3.exe'
 $db=Join-Path $root 'data\customers.db'
 $receipt=Join-Path $root 'state\customer-initial-load-accepted.txt'
 $idx=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $builder=Join-Path $root 'bin\build-bitrix-search-index.ps1'
 $query=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 foreach($file in @($legacy,$config,$exe,$db,$receipt,$curl,$ca)){
   if(-not [IO.File]::Exists($file)){Fail 'MACHINE_FILE_MISSING'}
   if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'FILE_REPARSE'}
 }
 if([IO.File]::Exists($idx) -or [IO.File]::Exists($builder) -or [IO.File]::Exists($query)){Fail 'PREVIOUS_INDEX_ATTEMPT_NEEDS_DIAGNOSIS'}
 $s3=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 if($s3 -notmatch ';ACCEPTANCE=PASS;IDENTITY=LOCAL_SERVICE;ROWS=6433;UNIQUE_GUIDS=6433;ACTIVE=6433;LEGAL=1941;PERSON=4486;REVIEW=6;INITIAL_RUNS=1;DB_INTEGRITY=ok;TEMP_TASK_REMOVED=YES;AUTO_START=OFF;ONEC_WRITES=0;BITRIX_CALLS=0$'){Fail 'S3_ACCEPTANCE_MISSING'}
 foreach($item in @(
   @($config,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),
   @($legacy,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0'))
 )){
   $raw=[IO.File]::ReadAllText([string]$item[0],[Text.Encoding]::ASCII)
   foreach($flag in $item[1]){
     if($raw -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_CONFIG_CHANGED'}
   }
 }
 if((ReadSql $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'CUSTOMER_ROWS_CHANGED'}
 if((ReadSql $exe $db "SELECT count(*) FROM sqlite_master WHERE name='customer_search_v1';") -ne '0'){Fail 'SEARCH_INDEX_ALREADY_PRESENT'}
 if((ReadSql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DATABASE_INTEGRITY_BAD'}
 $sched=New-Object -ComObject Schedule.Service
 $sched.Connect()
 $folder=$sched.GetFolder('\')
 $main=$folder.GetTask('MspCustomerStoreSync')
 if($null -eq $main){Fail 'MAIN_COLLECTOR_TASK_MISSING'}
 $runAs=$main.Definition.Principal.UserId
 if($runAs -eq 'S-1-5-19'){$sid=$runAs}else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $runAs).Translate([Security.Principal.SecurityIdentifier]).Value}
 if($sid -ne 'S-1-5-19'){Fail 'MAIN_TASK_WRONG_IDENTITY'}
 foreach($trigger in $main.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_AUTOSTART_ALREADY_ENABLED'}}
 $prior=$null
 try{$prior=$folder.GetTask('MspCustomerStoreBitrixIndex')}catch{}
 if($null -ne $prior){Fail 'INDEX_TASK_ALREADY_EXISTS'}
 $phase='VERIFIED_MACHINE_OWNED_DB_BACKUP'
 $backupDir=Join-Path $root 'backups'
 if(-not [IO.Directory]::Exists($backupDir)){Fail 'BACKUP_DIRECTORY_MISSING'}
 if(([IO.File]::GetAttributes($backupDir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'BACKUP_DIRECTORY_REPARSE'}
 $backup=Join-Path $backupDir 'customers-pre-bitrix-search-v1.db'
 if([IO.File]::Exists($backup)){Fail 'PREVIOUS_BACKUP_REQUIRES_DIAGNOSIS'}
 $command='.backup "'+$backup.Replace('\\','/')+'"'
 $backupResult=@(& $exe -readonly -batch -bail $db $command 2>&1)
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($backup)){Fail 'SQLITE_BACKUP_FAILED'}
 if(([IO.FileInfo]$backup).Length -lt 8192){Fail 'BACKUP_TOO_SMALL'}
 if((ReadSql $exe $backup 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKUP_INTEGRITY_FAILED'}
 if((ReadSql $exe $backup "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;") -ne '6433:6433'){Fail 'BACKUP_ROWS_MISMATCH'}
 'PRE_INDEX_BACKUP=PASS'
 $phase='STAGE_VERIFIED_BINARIES'
 $prefix='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/2da018a166db0805cffc99be608a76cab7587560/integrations/msp-bitrix24-bridge/bin/'
 foreach($spec in @(
   @('build-bitrix-search-index.ps1',$builder,'cb2a28aea36d7198941310b461acba93ff970475228c2aedaf02d270a2c4525e'),
   @('query-bitrix-search-index.ps1',$query,'1c3cf6832bf513a9b5b4f1ac4907bfa85b9b8119f7b91b005e64df4f05fe02f8')
 )){
   & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $spec[1] ($prefix+$spec[0])
   if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($spec[1])){Fail 'SOURCE_DOWNLOAD_FAILED'}
   if((Hash $spec[1]) -ne $spec[2]){Fail 'SOURCE_SHA256_MISMATCH'}
   $parseErrors=$null
   $null=[System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($spec[1],[Text.Encoding]::ASCII),[ref]$parseErrors)
   if($parseErrors -and $parseErrors.Count -gt 0){Fail 'PS2_SCRIPT_PARSE_FAILED'}
 }
 'SEARCH_SCRIPT_SHA256=PASS'
 'INDEX_BUILDER_SHA256=PASS'
 $phase='RUN_ONE_TIME_SERVICE_BUILD'
 $service=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $definition=$sched.NewTask(0)
 $definition.RegistrationInfo.Description='One-time SRV-only SQLite FTS5 search index preparation; no Bitrix calls'
 $definition.Principal.UserId=$service
 $definition.Principal.LogonType=5
 $definition.Principal.RunLevel=0
 $definition.Settings.Enabled=$true
 $definition.Settings.ExecutionTimeLimit='PT3M'
 $definition.Settings.MultipleInstances=2
 $act=$definition.Actions.Create(0)
 $act.Path=Join-Path $PSHOME 'powershell.exe'
 $act.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$builder+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition('MspCustomerStoreBitrixIndex',$definition,2,$service,$null,5,$null)
 $task=$folder.GetTask('MspCustomerStoreBitrixIndex')
 if($task.Definition.Triggers.Count -ne 0){Fail 'INDEX_TASK_HAS_TRIGGER'}
 $started=[DateTime]::UtcNow
 $null=$task.Run($null)
 $passed=$false
 for($i=0;$i -lt 180;$i++){
   Start-Sleep -Milliseconds 500
   if(-not [IO.File]::Exists($idx)){continue}
   $line=[IO.File]::ReadAllText($idx,[Text.Encoding]::ASCII).Trim()
   if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){
     $stamp=[DateTime]::Parse($Matches[1]).ToUniversalTime()
     if($stamp -ge $started.AddSeconds(-2)){$passed=$true;break}
   }
 }
 if(-not $passed){Fail 'INDEX_BUILD_NOT_ACCEPTED'}
 $phase='INDEX_SQLITE_BACKREAD'
 if((ReadSql $exe $db 'SELECT count(*) FROM customer_search_v1;') -ne '6433'){Fail 'INDEX_ROW_COUNT_MISMATCH'}
 if((ReadSql $exe $db "SELECT count(*) FROM customers;") -ne '6433'){Fail 'CUSTOMER_ROWS_CHANGED_AFTER_INDEX'}
 if((ReadSql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'INDEX_DB_INTEGRITY_FAILED'}
 $phase='CLEAN_TEMP_TASK'
 $folder.DeleteTask('MspCustomerStoreBitrixIndex',0)
 $again=$folder.GetTask('MspCustomerStoreSync')
 foreach($trigger in $again.Definition.Triggers){if($trigger.Enabled){Fail 'MAIN_AUTOSTART_CHANGED'}}
 'SEARCH_INDEX_CREATED=YES'
 'PRE_INDEX_BACKUP_VERIFIED=YES'
 'SEARCH_INDEX_ROWS=6433'
 'CUSTOMERS_REMAIN=6433'
 'SEARCH_INDEX_QUICK_CHECK=ok'
 'INDEX_CREATION_BY_LOCAL_SERVICE=PASS'
 'TEMPORARY_INDEX_TASK_REMOVED=YES'
 'MAIN_COLLECTOR_AUTOSTART=OFF'
 'NO_BITRIX_PORTAL_CONNECTION=YES'
 'CUSTOMER_DATA_EXPORTED=NO'
 'ONEC_CALLS=NO'
 'BITRIX_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_LOCAL_INDEX_ACCEPTANCE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^BRIDGE_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=SRV_BITRIX_LOCAL_INDEX_ACCEPTANCE;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}

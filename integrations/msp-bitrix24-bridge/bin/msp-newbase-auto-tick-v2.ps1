#requires -version 2
# One minute orchestrator for TEST NewBase -> SRV SQLite -> Bitrix24.
# Full 08:30 local SRV snapshot; count-trigger + 15-minute safety rescan.
param([string]$ExpectedComputerName='SRV',[int]$MaxBatchesPerTick=10)
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$state=Join-Path $root 'state\msp-newbase-auto-tick-v2.status'
$sourceState=Join-Path $root 'state\msp-newbase-auto-source-status.txt'
$scan=Join-Path $root 'bin\refresh-newbase-source-v2.ps1'
$count=Join-Path $root 'bin\count-newbase-active-v2.ps1'
$pump=Join-Path $root 'bin\pump-newbase-bitrix-batch-v2.ps1'
$phase='PRECHECK';$mutex=$null;$locked=$false
function Fail([string]$Code){throw ('TICK_'+$Code)}
function Worker([string]$Script,[string[]]$Params){
 $exe=Join-Path $PSHOME 'powershell.exe'
 $command=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Script,'-ExpectedComputerName','SRV')+$Params
 $out=@(& $exe $command 2>&1)
 $exit=$LASTEXITCODE
 if($exit -ne 0){Fail 'WORKER_EXIT_NONZERO'}
 return ($out -join [Environment]::NewLine)
}
try{
 $mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspNewbaseAutomatedTickV2')
 if(-not $mutex.WaitOne(0,$false)){ 'TICK_SKIPPED_ALREADY_RUNNING=YES'; exit 0 }
 $locked=$true
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_ONLY'}
 if($MaxBatchesPerTick -lt 1 -or $MaxBatchesPerTick -gt 15){Fail 'BATCH_COUNT_OUT_OF_RANGE'}
 foreach($f in @($scan,$count,$pump,(Join-Path $root 'bin\msp-newbase-bitrix-core-v2.ps1'))){
  if(-not [IO.File]::Exists($f)){Fail 'WORKER_MISSING'}
 }
 $now=[DateTime]::Now
 $sourceRows=-1;$last=[DateTime]::MinValue
 if([IO.File]::Exists($sourceState)){
  $t=[IO.File]::ReadAllText($sourceState,[Text.Encoding]::ASCII)
  if($t -match '^UTC=([^;]+);STATUS=PASS;SOURCE=TEST_NEWBASE;ROWS=([0-9]{1,8});'){
   $last=[DateTime]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AdjustToUniversal).ToLocalTime()
   $sourceRows=[int]$Matches[2]
  }
 }
 $daily=$now.Date.AddHours(8).AddMinutes(30)
 $needFull=$false;$reason='NONE'
 if($last -eq [DateTime]::MinValue){$needFull=$true;$reason='INITIAL'}
 elseif($now -ge $daily -and $last -lt $daily){$needFull=$true;$reason='DAILY_0830'}
 elseif(($now-$last).TotalMinutes -ge 15){$needFull=$true;$reason='SAFETY_RESCAN_15M'}
 else{
  $phase='CHECK_NEW_BUYER_COUNT'
  $out=Worker $count @()
  if($out -notmatch '(?m)^ACTIVE_BUYER_COUNT=([0-9]{1,8})\s*$'){Fail 'COUNT_REPLY_INVALID'}
  if([int]$Matches[1] -ne $sourceRows){$needFull=$true;$reason='BUYER_COUNT_CHANGED'}
 }
 $scanned='NO'
 if($needFull){
  $phase='REFRESH_TEST_NEWBASE'
  $out=Worker $scan @()
  if($out -notmatch 'RESULT=PASS;STAGE=MSP_NEWBASE_SOURCE_REFRESH'){Fail 'SOURCE_SCAN_NOT_CONFIRMED'}
  $scanned='YES'
 }
 $phase='PUMP_CRM_OUTBOX'
 $attempted=0;$confirmed=0
 for($k=0;$k -lt $MaxBatchesPerTick;$k++){
  $out=Worker $pump @('-MaxRows','20')
  if($out -notmatch 'RESULT=PASS;STAGE=NEWBASE_CRM_BATCH_V2'){Fail 'BATCH_NEEDS_RECONCILIATION'}
  if($out -match 'PENDING_ELIGIBLE_ITEMS=0'){break}
  if($out -notmatch '(?m)^NEWBASE_BATCH_SOURCE=([0-9]{1,2})\s*$'){Fail 'BATCH_REPLY_INVALID'}
  $attempted+=[int]$Matches[1]
  if($out -match '(?m)^CREATED_AND_VERIFIED=([0-9]+)'){$confirmed+=[int]$Matches[1]}
  Start-Sleep -Milliseconds 750
 }
 $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
 [IO.File]::WriteAllText($state,('UTC='+$stamp+';STATUS=PASS;SOURCE_SCAN='+$scanned+';REASON='+$reason+';BATCH_SOURCE='+$attempted+';CREATED='+$confirmed),[Text.Encoding]::ASCII)
 'SCAN='+$scanned
 'SCAN_REASON='+$reason
 'BATCH_SOURCE_ITEMS='+$attempted
 'CRM_CREATED='+$confirmed
 'SCHEDULER=ONE_MINUTE'
 'TEST_NEWBASE=YES'
 'RESULT=PASS;STAGE=MSP_NEWBASE_AUTO_TICK_V2'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^TICK_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($state,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=MSP_NEWBASE_AUTO_TICK_V2;GATE='+$gate+';PHASE='+$phase
 exit 1
}finally{
 if($locked){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Dispose()}
}
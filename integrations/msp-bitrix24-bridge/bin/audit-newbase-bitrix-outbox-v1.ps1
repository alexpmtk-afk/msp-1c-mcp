#requires -version 2
# Offline/LOCAL-SRV read-only aggregate counts for TEST NewBase Bitrix24 queue.
# Does not read or expose names, GUIDs, INN, tokens, or customer-level rows.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Code){throw ('OUTBOX_AUDIT_'+$Code)}
function Query([string]$Exe,[string]$Db,[string]$Sql){
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$Exe
 $psi.Arguments='-readonly -batch -bail "'+$Db+'"'
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.RedirectStandardInput=$true
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$psi
 try{
  if(-not $p.Start()){Fail 'SQLITE_START_FAILED'}
  $p.StandardInput.WriteLine($Sql)
  $p.StandardInput.Close()
  $stdout=$p.StandardOutput.ReadToEnd().Trim()
  $stderr=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(15000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $stderr.Trim().Length -gt 0){Fail 'SQLITE_QUERY_FAILED'}
  if($stdout.Length -gt 2048){Fail 'AGGREGATE_TOO_LONG'}
  if($stdout -notmatch '^[0-9A-Za-z_:|.-]*$'){Fail 'AGGREGATE_NOT_SAFE'}
  return $stdout
 }finally{$p.Close()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $db=Join-Path $root 'data\customers.db'
 $exe=Join-Path $root 'bin\sqlite3.exe'
 foreach($f in @($db,$exe)){
  if(-not [IO.File]::Exists($f)){Fail 'LOCAL_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT_DENIED'}
 }
 $phase='SQLITE_INTEGRITY'
 if((Query $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'SQLITE_INTEGRITY'}
 $phase='TABLE_DISCOVERY'
 $found=Query $exe $db "SELECT coalesce(group_concat(name,':'),'') FROM sqlite_master WHERE type='table' AND name IN ('customers','msp_auto_outbox','msp_auto_map','msp_auto_ops') ORDER BY name;"
 foreach($needed in @('customers','msp_auto_outbox','msp_auto_map','msp_auto_ops')){
  if(@($found.Split(':')) -notcontains $needed){
   'TABLE_MISSING='+$needed
  }
 }
 if(@($found.Split(':')) -notcontains 'customers'){Fail 'CUSTOMERS_TABLE_MISSING'}
 $phase='CUSTOMER_COUNTS'
 $c=Query $exe $db 'SELECT count(*) || ":" || count(DISTINCT onec_guid) || ":" || sum(CASE WHEN buyer=1 AND deletion_mark=0 AND invalid=0 THEN 1 ELSE 0 END) FROM customers;'
 if($c -notmatch '^[0-9]+:[0-9]+:[0-9]+$'){Fail 'CUSTOMER_COUNT_INVALID'}
 'CUSTOMERS_TOTAL_UNIQUE_ELIGIBLE='+$c
 if(@($found.Split(':')) -contains 'msp_auto_outbox'){
  $phase='OUTBOX_COUNTS'
  $q="SELECT count(*) || ':' || sum(CASE WHEN change_kind='UPSERT' THEN 1 ELSE 0 END) || ':' || sum(CASE WHEN change_kind='UPDATE_REQUIRED' THEN 1 ELSE 0 END) || ':' || sum(CASE WHEN change_kind='HELD' THEN 1 ELSE 0 END) || ':' || sum(CASE WHEN change_kind='REMOVED' THEN 1 ELSE 0 END) || ':' || sum(CASE WHEN change_kind NOT IN ('UPSERT','UPDATE_REQUIRED','HELD','REMOVED') THEN 1 ELSE 0 END) FROM msp_auto_outbox;"
  $s=Query $exe $db $q
  if($s -notmatch '^[0-9]+(:[0-9]+){5}$'){Fail 'OUTBOX_COUNTS_INVALID'}
  'OUTBOX_TOTAL_UPSERT_UPDATE_HELD_REMOVED_UNKNOWN='+$s
 }else{'OUTBOX=NOT_INITIALIZED'}
 if(@($found.Split(':')) -contains 'msp_auto_map'){
  $m=Query $exe $db 'SELECT count(*) FROM msp_auto_map;'
  if($m -notmatch '^[0-9]+$'){Fail 'MAPPING_COUNT_INVALID'}
  'CRM_LINKS='+$m
 }else{'CRM_LINKS=NOT_INITIALIZED'}
 if(@($found.Split(':')) -contains 'msp_auto_ops'){
  $o=Query $exe $db 'SELECT count(*) FROM msp_auto_ops;'
  if($o -notmatch '^[0-9]+$'){Fail 'OPS_COUNT_INVALID'}
  'UNRESOLVED_CRM_OPERATIONS='+$o
 }else{'UNRESOLVED_CRM_OPERATIONS=NOT_INITIALIZED'}
 'SOURCE=LOCAL_SQLITE_ONLY'
 'ONEC_REQUESTS=0'
 'BITRIX_REQUESTS=0'
 'CUSTOMER_DATA_EXPORTED=0'
 'RESULT=PASS;STAGE=NEWBASE_BITRIX_OUTBOX_READONLY_AUDIT'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^OUTBOX_AUDIT_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=NEWBASE_BITRIX_OUTBOX_READONLY_AUDIT;GATE='+$gate+';PHASE='+$phase
 exit 1
}

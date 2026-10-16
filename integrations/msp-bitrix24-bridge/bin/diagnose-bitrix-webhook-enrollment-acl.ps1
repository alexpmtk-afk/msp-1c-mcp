#requires -version 2
# One-shot non-secret diagnostics for failed SRV DPAPI webhook enrollment.
# Uses disposable named ACL probes, never accesses or prints a Bitrix24 webhook.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='START'
$probeDir=$null
$probeFile=$null
$stateFile=$null
$fs=$null
$secretBytes=$null
$sealedBytes=$null
$unsealedBytes=$null
$fail=$false
function Fail([string]$Code){throw ('DIAG_'+$Code)}
function Rule([string]$SidString,[string]$Right,[bool]$Inherit){
 $sid=New-Object Security.Principal.SecurityIdentifier -ArgumentList $SidString
 $rights=[Security.AccessControl.FileSystemRights]([Enum]::Parse([Security.AccessControl.FileSystemRights],$Right))
 if($Inherit){
  $flag=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
  return (New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @($sid,$rights,$flag,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
 }
 return (New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @($sid,$rights,[Security.AccessControl.AccessControlType]::Allow))
}
try{
 $phase='HOST_CHECK'
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'NATIVE_PS2_X64_REQUIRED'}
 'HOST_PS2_X64=PASS'
 $root='C:\ProgramData\MspCustomerStore'
 $staging=Join-Path $root 'staging'
 $state=Join-Path $root 'state'
 $existing=Join-Path $staging 'bitrix-direct-private'
 $receipt=Join-Path $state 'bitrix-direct-webhook-enrolled.txt'
 $phase='BASELINE'
 foreach($d in @($root,$staging,$state)){
  if(-not [IO.Directory]::Exists($d)){Fail 'MISSING_BASE_DIRECTORY'}
  if(([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'BASE_REPARSE'}
 }
 if([IO.Directory]::Exists($existing) -or [IO.File]::Exists($receipt)){Fail 'ALREADY_ENROLLED_OR_PARTIAL'}
 'BASELINE=PASS'
 $phase='COLLECTOR_CONFIG_READ'
 $collector=Join-Path $root 'config\collector.ini'
 if(-not [IO.File]::Exists($collector)){Fail 'COLLECTOR_CONFIG_MISSING'}
 $idle=[IO.File]::ReadAllText($collector,[Text.Encoding]::ASCII)
 foreach($gate in @('ACTIVE=0','BITRIX=0')){
  if($idle -notmatch ('(?m)^'+$gate+'\s*$')){Fail 'COLLECTOR_NOT_IDLE'}
 }
 'COLLECTOR_SAFE_IDLE=PASS'
 $phase='LEGACY_WORKER_CHECK'
 foreach($f in @('config\bitrix-search-worker.ini','secrets\bitrix-search-worker.dpapi')){
  if([IO.File]::Exists((Join-Path $root $f))){Fail 'OLD_RELAY_CONFIG_PRESENT'}
 }
 'LEGACY_WORKER_DISABLED=PASS'
 $phase='ACCOUNT_SID'
 $who=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($who -notmatch '^S-1-5-[0-9-]+$'){Fail 'IDENTITY_INVALID'}
 'CURRENT_ACCOUNT_SID=PASS'
 $name='bitrix-direct-acl-test-'+[Guid]::NewGuid().ToString('N')
 $probeDir=Join-Path $staging $name
 $probeFile=Join-Path $probeDir 'test.dat'
 $stateFile=Join-Path $state ($name+'.tmp')
 $phase='PRIVATE_DIR_CREATE'
 [void][IO.Directory]::CreateDirectory($probeDir)
 'PRIVATE_DIR_CREATE=PASS'
 $phase='DIR_ACL_CONSTRUCT'
 $acl=[IO.Directory]::GetAccessControl($probeDir)
 $acl.SetAccessRuleProtection($true,$false)
 foreach($e in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-19','ReadAndExecute'),@($who,'Modify'))){
  $acl.AddAccessRule((Rule ([string]$e[0]) ([string]$e[1]) $true))
 }
 'DIR_ACL_CONSTRUCT=PASS'
 $phase='DIR_ACL_APPLY'
 [IO.Directory]::SetAccessControl($probeDir,$acl)
 'DIR_ACL_APPLY=PASS'
 $phase='DIR_ACL_READBACK'
 $acl2=[IO.Directory]::GetAccessControl($probeDir)
 $ok=$false
 foreach($rr in $acl2.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
  if($rr.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow){
   if(@('S-1-5-18','S-1-5-19','S-1-5-32-544',$who) -notcontains $rr.IdentityReference.Value){Fail 'UNEXPECTED_DIR_READER'}
   if($rr.IdentityReference.Value -eq 'S-1-5-19'){$ok=$true}
  }
 }
 if(-not $ok){Fail 'LOCAL_SERVICE_NOT_GRANTED'}
 'DIR_ACL_READBACK=PASS'
 $phase='FILE_CREATE'
 $fs=New-Object IO.FileStream -ArgumentList @($probeFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 $fs.Close();$fs=$null
 'FILE_CREATE=PASS'
 $phase='FILE_ACL_CONSTRUCT'
 $fileAcl=New-Object Security.AccessControl.FileSecurity
 $fileAcl.SetAccessRuleProtection($true,$false)
 foreach($e in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-19','Read'),@($who,'Modify'))){
  $fileAcl.AddAccessRule((Rule ([string]$e[0]) ([string]$e[1]) $false))
 }
 'FILE_ACL_CONSTRUCT=PASS'
 $phase='FILE_ACL_APPLY'
 [IO.File]::SetAccessControl($probeFile,$fileAcl)
 'FILE_ACL_APPLY=PASS'
 $phase='DUMMY_DPAPI'
 Add-Type -AssemblyName System.Security
 $secretBytes=[Text.Encoding]::ASCII.GetBytes('dummy-test-value-only')
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-Bitrix24-Direct-Webhook-v1')
 $sealedBytes=[Security.Cryptography.ProtectedData]::Protect($secretBytes,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 $unsealedBytes=[Security.Cryptography.ProtectedData]::Unprotect($sealedBytes,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 if([Text.Encoding]::ASCII.GetString($unsealedBytes) -cne 'dummy-test-value-only'){Fail 'DUMMY_DPAPI_ROUNDTRIP_MISMATCH'}
 'DPAPI_DUMMY_ROUNDTRIP=PASS'
 $phase='PRIVATE_FILE_WRITE'
 $fs=New-Object IO.FileStream -ArgumentList @($probeFile,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
 $fs.Write($sealedBytes,0,$sealedBytes.Length);$fs.Flush();$fs.Close();$fs=$null
 'PRIVATE_FILE_WRITE=PASS'
 $phase='STATE_FILE_WRITE'
 $fs=New-Object IO.FileStream -ArgumentList @($stateFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 $row=[Text.Encoding]::ASCII.GetBytes('dummy-test-status-only')
 $fs.Write($row,0,$row.Length);$fs.Close();$fs=$null
 'STATE_FILE_WRITE=PASS'
 'RESULT=PASS;STAGE=BITRIX_WEBHOOK_ENROLLMENT_SAFE_ACL_DIAGNOSTIC'
}catch{
 $fail=$true
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^DIAG_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=BITRIX_WEBHOOK_ENROLLMENT_SAFE_ACL_DIAGNOSTIC;PHASE='+$phase+';GATE='+$gate+';EXCEPTION_TYPE='+$_.Exception.GetType().Name
}finally{
 if($null -ne $fs){try{$fs.Close()}catch{}}
 $removed=$true
 if($null -ne $stateFile -and [IO.File]::Exists($stateFile)){try{[IO.File]::Delete($stateFile)}catch{$removed=$false}}
 if($null -ne $probeDir -and [IO.Directory]::Exists($probeDir)){try{[IO.Directory]::Delete($probeDir,$true)}catch{$removed=$false}}
 if($null -ne $secretBytes){[Array]::Clear($secretBytes,0,$secretBytes.Length)}
 if($null -ne $sealedBytes){[Array]::Clear($sealedBytes,0,$sealedBytes.Length)}
 if($null -ne $unsealedBytes){[Array]::Clear($unsealedBytes,0,$unsealedBytes.Length)}
 'TEMP_TEST_FILES_REMOVED='+$(if($removed){'YES'}else{'NO'})
 'WEBHOOK_READ=NO'
 'WEBHOOK_SAVED=NO'
 'BITRIX_CALLS=NO'
 'ONEC_CALLS=NO'
 if($fail){exit 1}
}
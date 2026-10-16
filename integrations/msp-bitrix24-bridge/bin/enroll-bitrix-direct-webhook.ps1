#requires -version 2
# One-time enrollment on physical SRV: machine DPAPI, no webhook URL in arguments, GitHub, logs, or stdout.
# Does not create any scheduled task, enable agents, contact 1C, or call Bitrix API.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$secure=$null
$ptr=[IntPtr]::Zero
$plain=$null
$clearBytes=$null
$sealedBytes=$null
$verify=$null
$fs=$null
$secret=$null
$created=$false
function Fail([string]$Code){throw ('ENROLL_'+$Code)}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $root='C:\ProgramData\MspCustomerStore'
 $dir=Join-Path $root 'secrets'
 $secret=Join-Path $dir 'bitrix-direct-webhook.dpapi'
 $receipt=Join-Path $root 'state\bitrix-direct-webhook-enrolled.txt'
 foreach($d in @($root,$dir)){
  if(-not [IO.Directory]::Exists($d)){Fail 'DIRECTORY_MISSING'}
  if(([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'DIRECTORY_REPARSE'}
 }
 if([IO.File]::Exists($secret) -or [IO.File]::Exists($receipt)){Fail 'ALREADY_ENROLLED_STOP'}
 if(-not [IO.File]::Exists((Join-Path $root 'state\bitrix-direct-crm-readonly-status.txt'))){Fail 'DIRECT_CRM_NOT_YET_PROVEN'}
 $collector=Join-Path $root 'config\collector.ini'
 if(-not [IO.File]::Exists($collector)){Fail 'COLLECTOR_CONFIG_MISSING'}
 $idle=[IO.File]::ReadAllText($collector,[Text.Encoding]::ASCII)
 foreach($gate in @('ACTIVE=0','BITRIX=0')){
  if($idle -notmatch ('(?m)^'+$gate+'\s*$')){Fail 'COLLECTOR_NOT_SAFE_IDLE'}
 }
 foreach($f in @('config\bitrix-search-worker.ini','secrets\bitrix-search-worker.dpapi')){
  if([IO.File]::Exists((Join-Path $root $f))){Fail 'OLD_RELAY_CONFIG_PRESENT'}
 }
 # Validate directory DACL is not publicly writable or readable before accepting any secret.
 $dirAcl=[IO.Directory]::GetAccessControl($dir)
 $rules=$dirAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
 foreach($rule in $rules){
  if($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){continue}
  if(@('S-1-5-18','S-1-5-19','S-1-5-32-544') -notcontains $rule.IdentityReference.Value){Fail 'SECRET_DIRECTORY_PERMISSIONS_UNEXPECTED'}
 }
 $who=[Security.Principal.WindowsIdentity]::GetCurrent().User
 $whoSid=$who.Value
 Add-Type -AssemblyName System.Security
 # Create an empty placeholder first, then restrict its ACL, before asking for the webhook.
 try{
  $fs=New-Object IO.FileStream -ArgumentList @($secret,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $created=$true
 }catch [UnauthorizedAccessException]{Fail 'SECRET_DIRECTORY_WRITE_DENIED'}
 $fileAcl=New-Object Security.AccessControl.FileSecurity
 $fileAcl.SetAccessRuleProtection($true,$false)
 foreach($entry in @(
   @('S-1-5-18','FullControl'),
   @('S-1-5-32-544','FullControl'),
   @('S-1-5-19','Read'),
   @($whoSid,'Read')
  )){
  $sid=New-Object Security.Principal.SecurityIdentifier -ArgumentList ([string]$entry[0])
  $right=[Security.AccessControl.FileSystemRights]([Enum]::Parse([Security.AccessControl.FileSystemRights],[string]$entry[1]))
  $rule=New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @($sid,$right,[Security.AccessControl.AccessControlType]::Allow)
  $fileAcl.AddAccessRule($rule)
 }
 $fs.SetAccessControl($fileAcl)
 $fs.Close();$fs=$null
 $secure=Read-Host -Prompt 'Enter Bitrix24 incoming webhook BASE URL ONCE (hidden; do not share)' -AsSecureString
 if($null -eq $secure -or $secure.Length -lt 45 -or $secure.Length -gt 220){Fail 'WEBHOOK_LENGTH_INVALID'}
 $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
 $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
 [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr);$ptr=[IntPtr]::Zero
 if($plain -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/?$'){Fail 'WEBHOOK_HOST_INVALID'}
 $plain=$plain.TrimEnd('/')+'/'
 $clearBytes=[Text.Encoding]::UTF8.GetBytes($plain)
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-Bitrix24-Direct-Webhook-v1')
 $sealedBytes=[Security.Cryptography.ProtectedData]::Protect($clearBytes,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 if($sealedBytes.Length -lt 64 -or $sealedBytes.Length -gt 4096){Fail 'DPAPI_OUTPUT_SIZE'}
 $fs=New-Object IO.FileStream -ArgumentList @($secret,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
 $fs.Write($sealedBytes,0,$sealedBytes.Length);$fs.Flush()
 $fs.Close();$fs=$null
 $verify=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($secret),$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 if([Text.Encoding]::UTF8.GetString($verify) -cne $plain){Fail 'DPAPI_VERIFY_FAILED'}
 $line='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SECRET=bitrix-direct-webhook.dpapi;STORAGE=MACHINE_DPAPI;READERS=SYSTEM_ADMINS_LOCAL_SERVICE_ENROLLER;WEBHOOK_PRINTED=NO;COLLECTOR_ENABLED=NO;BITRIX_CALLS=0;ONEC_CALLS=0'
 $status=New-Object IO.FileStream -ArgumentList @($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$raw=[Text.Encoding]::ASCII.GetBytes($line);$status.Write($raw,0,$raw.Length);$status.Flush()}finally{$status.Close()}
 'BITRIX_DIRECT_WEBHOOK_ENROLLED=PASS'
 'STORAGE=MACHINE_DPAPI'
 'SECRET_PATH='+$secret
 'AUTHORIZED_READERS=SYSTEM,ADMINISTRATORS,LOCAL_SERVICE,ENROLLER'
 'WEBHOOK_URL_PRINTED=NO'
 'COLLECTOR_AUTOSTART_UNCHANGED=YES'
 'BITRIX_CALLS=NO'
 'ONEC_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_DIRECT_WEBHOOK_ENROLLMENT'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^ENROLL_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 if($created -and $null -ne $secret -and [IO.File]::Exists($secret) -and -not [IO.File]::Exists((Join-Path 'C:\ProgramData\MspCustomerStore' 'state\bitrix-direct-webhook-enrolled.txt'))){
  try{if($null -ne $fs){$fs.Close();$fs=$null};[IO.File]::Delete($secret)}catch{}
 }
 'RESULT=FAIL;STAGE=SRV_BITRIX_DIRECT_WEBHOOK_ENROLLMENT;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}finally{
 if($null -ne $fs){$fs.Close()}
 if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
 if($null -ne $clearBytes){[Array]::Clear($clearBytes,0,$clearBytes.Length)}
 if($null -ne $sealedBytes){[Array]::Clear($sealedBytes,0,$sealedBytes.Length)}
 if($null -ne $verify){[Array]::Clear($verify,0,$verify.Length)}
 if($null -ne $secure){$secure.Dispose()}
 $plain=$null
}
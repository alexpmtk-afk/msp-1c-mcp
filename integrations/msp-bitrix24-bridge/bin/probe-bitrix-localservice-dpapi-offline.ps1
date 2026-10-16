#requires -version 2
# One-time LOCAL SERVICE-only offline DPAPI verification; never sends or prints webhook.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$receipt=Join-Path $root 'state\bitrix-localservice-dpapi-status.txt'
$blob=$null
$clear=$null
$url=$null
function Fail([string]$Code){throw ('SERVICE_DPAPI_'+$Code)}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 if([IO.File]::Exists($receipt)){Fail 'PRIOR_TEST_PRESENT'}
 $proof=Join-Path $root 'state\bitrix-direct-webhook-enrolled.txt'
 $secret=Join-Path $root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'
 if(-not [IO.File]::Exists($proof) -or -not [IO.File]::Exists($secret)){Fail 'ENROLLMENT_MISSING'}
 foreach($f in @($proof,$secret)){
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
 }
 $mark=[IO.File]::ReadAllText($proof,[Text.Encoding]::ASCII).Trim()
 if($mark -notmatch '^UTC=[^;]+;STATUS=PASS;SECRET=bitrix-direct-private/bitrix-direct-webhook.dpapi;STORAGE=MACHINE_DPAPI;READERS=SYSTEM_ADMINS_LOCAL_SERVICE_ENROLLER;WEBHOOK_PRINTED=NO;COLLECTOR_ENABLED=NO;BITRIX_CALLS=0;ONEC_CALLS=0$'){Fail 'ENROLLMENT_NOT_ACCEPTED'}
 Add-Type -AssemblyName System.Security
 $blob=[IO.File]::ReadAllBytes($secret)
 if($blob.Length -lt 64 -or $blob.Length -gt 4096){Fail 'BLOB_SIZE_INVALID'}
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-Bitrix24-Direct-Webhook-v1')
 $clear=[Security.Cryptography.ProtectedData]::Unprotect($blob,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 $url=[Text.Encoding]::UTF8.GetString($clear)
 if($url -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/$'){Fail 'HOST_FORMAT_INVALID'}
 $line='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;IDENTITY=LOCAL_SERVICE;DPAPI_UNPROTECT=PASS;WEBHOOK_HOST=VALID;SECRET_PRINTED=NO;BITRIX_CALLS=0;ONEC_CALLS=0'
 $fs=New-Object IO.FileStream -ArgumentList @($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$data=[Text.Encoding]::ASCII.GetBytes($line);$fs.Write($data,0,$data.Length);$fs.Flush()}finally{$fs.Close()}
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^SERVICE_DPAPI_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{
  if(-not [IO.File]::Exists($receipt)){
   $line='STATUS=FAIL;IDENTITY=LOCAL_SERVICE;GATE='+$gate
   $fs=New-Object IO.FileStream -ArgumentList @($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
   try{$data=[Text.Encoding]::ASCII.GetBytes($line);$fs.Write($data,0,$data.Length);$fs.Flush()}finally{$fs.Close()}
  }
 }catch{}
 exit 1
}finally{
 if($null -ne $blob){[Array]::Clear($blob,0,$blob.Length)}
 if($null -ne $clear){[Array]::Clear($clear,0,$clear.Length)}
 $url=$null
}
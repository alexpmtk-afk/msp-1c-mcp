#requires -version 2
# One-time machine DPAPI enrollment and LOCAL SERVICE read-only 1C TEST proof.
# Password is entered ONLY in the SRV console, never in args, logs or GitHub.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$secretData=$null
$protectedBytes=$null
$ptr=[IntPtr]::Zero
$secure=$null
function Fail([string]$Reason){throw ('PROVISION_'+$Reason)}
function Sha([string]$File){
  $h=New-Object Security.Cryptography.SHA256Managed
  try{$hash=$h.ComputeHash([IO.File]::ReadAllBytes($File));return ([BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant()}
  finally{$h.Clear()}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
  $who=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
  if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ELEVATION_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $bin=Join-Path $root 'bin'
  $secrets=Join-Path $root 'secrets'
  $stateDir=Join-Path $root 'state'
  $config=Join-Path $root 'config\collector.ini'
  $legacy='C:\ProgramData\MspBitrix24Bridge\config\bridge.ini'
  $curl=Join-Path $bin 'curl.exe'
  $ca=Join-Path $root 'config\curl-ca-bundle.crt'
  $script=Join-Path $bin 'probe-onec-service-readonly.ps1'
  $secret=Join-Path $secrets 'onec-test-odata.dpapi'
  $status=Join-Path $stateDir 'onec-readonly-proof.txt'
  foreach($dir in @($root,$bin,$secrets,$stateDir)){
    if(-not [IO.Directory]::Exists($dir)){Fail 'MACHINE_DIRECTORY_MISSING'}
    if(([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DIRECTORY'}
  }
  if(-not [IO.File]::Exists($config) -or -not [IO.File]::Exists($legacy) -or -not [IO.File]::Exists($curl) -or -not [IO.File]::Exists($ca)){Fail 'MACHINE_CONFIG_MISSING'}
  foreach($row in @(@($config,@('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')),@($legacy,@('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')))){
    $text=[IO.File]::ReadAllText([string]$row[0],[Text.Encoding]::ASCII)
    foreach($flag in $row[1]){
      if($text -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_NOT_CONFIRMED'}
    }
  }
  if([IO.File]::Exists($secret) -or [IO.File]::Exists($script) -or [IO.File]::Exists($status)){Fail 'ENROLLMENT_ALREADY_PRESENT'}
  $acl=[IO.Directory]::GetAccessControl($secrets)
  $rules=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
  $serviceRead=$false
  foreach($rule in $rules){
    if($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){continue}
    if(@('S-1-5-18','S-1-5-19','S-1-5-32-544') -notcontains $rule.IdentityReference.Value){Fail 'UNEXPECTED_SECRET_DIRECTORY_READER'}
    if($rule.IdentityReference.Value -eq 'S-1-5-19'){$serviceRead=$true}
  }
  if(-not $serviceRead){Fail 'SERVICE_SECRET_READ_PERMISSION_MISSING'}
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $collector=$folder.GetTask('MspCustomerStoreSync')
  if($null -eq $collector){Fail 'COLLECTOR_TASK_MISSING'}
  $runAs=$collector.Definition.Principal.UserId
  if($runAs -eq 'S-1-5-19'){$sid=$runAs}else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $runAs).Translate([Security.Principal.SecurityIdentifier]).Value}
  if($sid -ne 'S-1-5-19'){Fail 'COLLECTOR_IDENTITY_MISMATCH'}
  foreach($trigger in $collector.Definition.Triggers){if($trigger.Enabled){Fail 'COLLECTOR_AUTOSTART_PREMATURE'}}
  $existing=$null
  try{$existing=$folder.GetTask('MspCustomerStoreCredentialProof')}catch{}
  if($null -ne $existing){Fail 'PROOF_TASK_ALREADY_EXISTS'}
  $phase='STAGE_VERIFIER'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/b3c45db7f5c40f9b33ef79afa2ac1ac5bfc68d4d/integrations/msp-bitrix24-bridge/bin/probe-onec-service-readonly.ps1'
  & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $script $url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($script)){Fail 'VERIFIER_DOWNLOAD_FAILED'}
  if((Sha $script) -ne '1620c8cb2ff30cd2a9260ddf22d65b5fb492ef194a0099f0a1235595aad95669'){Fail 'VERIFIER_SHA256_MISMATCH'}
  $errors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($script,[Text.Encoding]::ASCII),[ref]$errors)
  if($errors -and $errors.Count -gt 0){Fail 'VERIFIER_PS2_PARSE_FAILED'}
  $phase='ENCRYPT_SECRET'
  Add-Type -AssemblyName System.Security
  $secure=Read-Host -Prompt 'Password for MCP_OData_ReadOnly (stored machine-encrypted)' -AsSecureString
  if($null -eq $secure -or $secure.Length -eq 0){Fail 'PASSWORD_REQUIRED'}
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $length=[Runtime.InteropServices.Marshal]::ReadInt32($ptr,-4)
  if($length -lt 2 -or $length -gt 1024 -or ($length % 2) -ne 0){Fail 'PASSWORD_LENGTH_INVALID'}
  $secretData=New-Object byte[] $length
  [Runtime.InteropServices.Marshal]::Copy($ptr,$secretData,0,$length)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  $ptr=[IntPtr]::Zero
  $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
  $protectedBytes=[Security.Cryptography.ProtectedData]::Protect($secretData,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  [Array]::Clear($secretData,0,$secretData.Length)
  $secretData=$null
  $stream=New-Object IO.FileStream -ArgumentList @($secret,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($protectedBytes,0,$protectedBytes.Length);$stream.Flush()}finally{$stream.Close()}
  'SECRET_MACHINE_DPAPI=STORED'
  'SECRET_PLAINTEXT_FILE_CREATED=NO'
  $phase='RUN_LOCAL_SERVICE_PROOF'
  $account=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $definition=$scheduler.NewTask(0)
  $definition.RegistrationInfo.Description='One-time machine OData read-only credential test; no startup triggers'
  $definition.Principal.UserId=$account
  $definition.Principal.LogonType=5
  $definition.Principal.RunLevel=0
  $definition.Settings.Enabled=$true
  $definition.Settings.ExecutionTimeLimit='PT2M'
  $definition.Settings.MultipleInstances=2
  $action=$definition.Actions.Create(0)
  $action.Path=(Join-Path $PSHOME 'powershell.exe')
  $action.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$script+'" -ExpectedComputerName SRV'
  $null=$folder.RegisterTaskDefinition('MspCustomerStoreCredentialProof',$definition,2,$account,$null,5,$null)
  $task=$folder.GetTask('MspCustomerStoreCredentialProof')
  if($task.Definition.Triggers.Count -ne 0){Fail 'PROOF_AUTOMATIC_TRIGGER_UNEXPECTED'}
  $start=[DateTime]::UtcNow
  $null=$task.Run($null)
  $passed=$false
  $count=0
  for($i=0;$i -lt 100;$i++){
    Start-Sleep -Milliseconds 500
    if(-not [IO.File]::Exists($status)){continue}
    $line=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII).Trim()
    if($line -match '^STATUS=FAIL;PHASE=([A-Z0-9_]+);GATE=([A-Z0-9_]+)$'){
      'ONEC_PROOF_FAILURE_PHASE='+$Matches[1]
      'ONEC_PROOF_FAILURE_GATE='+$Matches[2]
      Fail 'SERVICE_ODATA_PROOF_FAILED'
    }
    if($line -match '^UTC=([^;]+);STATUS=PASS;IDENTITY=LOCAL_SERVICE;HTTP=200;BUYER_COUNT=([0-9]{1,8});RECORDS_EXPORTED=0;ONEC_WRITES=0$'){
      $stamp=[DateTime]::Parse($Matches[1]).ToUniversalTime()
      if($stamp -ge $start.AddSeconds(-2)){$passed=$true;$count=[int]::Parse($Matches[2]);break}
    }
  }
  if(-not $passed){Fail 'SERVICE_ODATA_PROOF_NOT_CONFIRMED'}
  $phase='PROOF_CLEANUP'
  $folder.DeleteTask('MspCustomerStoreCredentialProof',0)
  'SERVICE_DPAPI_UNPROTECT=PASS'
  'SERVICE_ONEC_READONLY_HTTP=200'
  'SERVICE_ACTIVE_BUYER_COUNT='+$count
  'PROOF_TASK_DELETED=YES'
  'COLLECTOR_AUTOSTART=OFF'
  'CUSTOMER_DB_UNCHANGED=YES'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_ONEC_SERVICE_CREDENTIAL_PROVISION'
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^PROVISION_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_ONEC_SERVICE_CREDENTIAL_PROVISION;GATE='+$gate+';PHASE='+$phase
  'NO_AUTOMATIC_RETRY=YES'
  exit 1
}finally{
  if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
  if($null -ne $secretData){[Array]::Clear($secretData,0,$secretData.Length)}
  if($null -ne $protectedBytes){[Array]::Clear($protectedBytes,0,$protectedBytes.Length)}
  if($null -ne $secure){$secure.Dispose()}
}

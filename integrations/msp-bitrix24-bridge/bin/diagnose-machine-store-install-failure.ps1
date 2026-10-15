#requires -version 2
# Read-only diagnosis of partial machine-owned store installation.
# Safe for Windows Server 2008 R2, PowerShell 2.0; changes nothing.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
function Fail([string]$Reason){throw ('STORE_DIAG_'+$Reason)}
function Probe([string]$Label,[string]$Path){
  if([IO.File]::Exists($Path)){
    'PATH='+$Label+';STATUS=FILE_CONFLICT'
    return
  }
  if(-not [IO.Directory]::Exists($Path)){
    'PATH='+$Label+';STATUS=MISSING'
    return
  }
  'PATH='+$Label+';STATUS=EXISTS'
  try{
    $attributes=[IO.File]::GetAttributes($Path)
    $reparse=(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    'PATH='+$Label+';REPARSE='+$reparse
    if($reparse){return}
    $acl=[IO.Directory]::GetAccessControl($Path)
    'PATH='+$Label+';ACL_PROTECTED='+$acl.AreAccessRulesProtected
    $rules=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
    $sidList=@('S-1-5-18','S-1-5-19','S-1-5-32-544')
    foreach($sid in $sidList){
      $allow=$false
      $deny=$false
      $writeAllow=$false
      $inherited=$false
      foreach($ace in $rules){
        if($ace.IdentityReference.Value -ne $sid){continue}
        if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow){
          $allow=$true
          if(($ace.FileSystemRights -band [Security.AccessControl.FileSystemRights]::WriteData) -ne 0){$writeAllow=$true}
        }
        if($ace.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny){$deny=$true}
        if($ace.IsInherited){$inherited=$true}
      }
      'PATH='+$Label+';SID='+$sid+';ALLOW='+$allow+';WRITE_ACE='+$writeAllow+';DENY='+$deny+';INHERITED='+$inherited
    }
  }catch{
    'PATH='+$Label+';ACL_READ=FAILED'
  }
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  'HOST='+$env:COMPUTERNAME
  'RUN_AS_ADMIN='+$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  'POWERSHELL_MAJOR='+$PSVersionTable.PSVersion.Major
  'PROGRAMDATA_RESOLVED='+[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
  $root='C:\ProgramData\MspCustomerStore'
  $parent='C:\ProgramData'
  $icacls=Join-Path $env:WINDIR 'System32\icacls.exe'
  'ICACLS_EXISTS='+[IO.File]::Exists($icacls)
  $phase='DIRECTORY_INSPECTION'
  Probe 'PROGRAMDATA_PARENT' $parent
  Probe 'CUSTOMER_ROOT' $root
  foreach($name in @('bin','config','schema','data','state','logs','staging','secrets','backups')){
    Probe ('CUSTOMER_'+$name.ToUpperInvariant()) (Join-Path $root $name)
  }
  $phase='TASK_INSPECTION'
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $task=$null
  try{$task=$scheduler.GetFolder('\').GetTask('MspCustomerStoreSync')}catch{}
  'COLLECTOR_TASK_EXISTS='+($null -ne $task)
  if($null -ne $task){
    'COLLECTOR_TASK_ENABLED='+$task.Enabled
    $sid='UNKNOWN'
    try{
      $owner=$task.Definition.Principal.UserId
      if($owner -eq 'S-1-5-19'){$sid='S-1-5-19'}
      else{$sid=(New-Object Security.Principal.NTAccount -ArgumentList $owner).Translate([Security.Principal.SecurityIdentifier]).Value}
    }catch{}
    'COLLECTOR_TASK_LOCAL_SERVICE='+($sid -eq 'S-1-5-19')
    $boot=$false
    foreach($trigger in $task.Definition.Triggers){
      if($trigger.Type -eq 8 -and $trigger.Enabled){$boot=$true}
    }
    'COLLECTOR_TASK_BOOT_ENABLED='+$boot
  }
  $phase='FILE_INSPECTION'
  'SQLITE_EXE_PRESENT='+[IO.File]::Exists((Join-Path $root 'bin\sqlite3.exe'))
  'COLLECTOR_CONFIG_PRESENT='+[IO.File]::Exists((Join-Path $root 'config\collector.ini'))
  'COLLECTOR_DB_PRESENT='+[IO.File]::Exists((Join-Path $root 'data\customers.db'))
  'COLLECTOR_SMOKE_PRESENT='+[IO.File]::Exists((Join-Path $root 'bin\smoke-customer-store-service.ps1'))
  'COLLECTOR_HTTPS_CLIENT_PRESENT='+[IO.File]::Exists((Join-Path $root 'bin\curl.exe'))
  'FILE_WRITES=NO'
  'ACL_CHANGES=NO'
  'TASK_CHANGES=NO'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_PARTIAL_INSTALL_DIAG'
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^STORE_DIAG_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_PARTIAL_INSTALL_DIAG;GATE='+$gate+';PHASE='+$phase
}finally{
  'NO_INSTALL_RETRY=YES'
}

#requires -version 2
# Read-only pinpoint of partially completed machine-owned customer-store installer.
# No network requests, no file/task/ACL writes, no personal records.
param([string]$ExpectedComputerName='SRV',[string]$BootstrapTlsDir='C:\Users\parshin\Desktop\OnecHttpsPortable_20261013_095710')
$ErrorActionPreference='Stop'
function Sha([string]$File){
  $h=New-Object Security.Cryptography.SHA256Managed
  try{
    $bytes=[IO.File]::ReadAllBytes($File)
    $digest=$h.ComputeHash($bytes)
    return ([BitConverter]::ToString($digest)).Replace('-','').ToLowerInvariant()
  }finally{$h.Clear()}
}
function InspectFile([string]$Label,[string]$File){
  $exists=[IO.File]::Exists($File)
  ($Label+'_PRESENT='+$exists)
  if($exists){
    try{
      $fi=New-Object IO.FileInfo -ArgumentList $File
      ($Label+'_BYTES='+$fi.Length)
      ($Label+'_REPARSE='+((($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)))
    }catch{($Label+'_DETAILS=UNAVAILABLE')}
  }
}
function ExecVersion([string]$Label,[string]$Executable){
  if(-not [IO.File]::Exists($Executable)){($Label+'_VERSION_STATUS=NOT_PRESENT');return}
  try{
    $result=@(& $Executable --version 2>&1)
    $exit=$LASTEXITCODE
    if($exit -eq 0 -and (($result -join ' ') -match '(?i)curl/')){
      ($Label+'_VERSION_STATUS=PASS')
    }else{
      ($Label+'_VERSION_STATUS=FAIL')
      ($Label+'_VERSION_EXIT='+$exit)
    }
  }catch{
    ($Label+'_VERSION_STATUS=EXCEPTION')
    ($Label+'_VERSION_EXCEPTION_TYPE='+$_.Exception.GetType().Name)
  }
}
function HasReadAcl([string]$Label,[string]$Path){
  try{
    if(-not [IO.Directory]::Exists($Path)){($Label+'_ACL=DIR_MISSING');return}
    $acl=[IO.Directory]::GetAccessControl($Path)
    $rules=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
    $admins=$false
    foreach($rule in $rules){
      if($rule.IdentityReference.Value -eq 'S-1-5-32-544' -and $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow){
        $admins=$true
      }
    }
    ($Label+'_ADMINS_ALLOW='+$admins)
  }catch{($Label+'_ACL=UNAVAILABLE')}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){throw 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){throw 'PS2_REQUIRED'}
  $root='C:\ProgramData\MspCustomerStore'
  $bin=Join-Path $root 'bin'
  $cfg=Join-Path $root 'config'
  if(-not [IO.Directory]::Exists($root)){throw 'COLLECTOR_ROOT_MISSING'}
  if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'COLLECTOR_ROOT_REPARSE'}
  if(-not [IO.Directory]::Exists($bin) -or -not [IO.Directory]::Exists($cfg)){throw 'BIN_OR_CONFIG_DIR_MISSING'}
  $srcExe=Join-Path $BootstrapTlsDir 'curl.exe'
  $srcCa=Join-Path $BootstrapTlsDir 'curl-ca-bundle.crt'
  $destExe=Join-Path $bin 'curl.exe'
  $destCa=Join-Path $cfg 'curl-ca-bundle.crt'
  'HOST='+$env:COMPUTERNAME
  'DIAG_STAGE=TLS_INSTALL_BLOCK'
  HasReadAcl 'BIN' $bin
  HasReadAcl 'CONFIG' $cfg
  InspectFile 'SOURCE_CURL' $srcExe
  InspectFile 'TARGET_CURL' $destExe
  InspectFile 'SOURCE_CA' $srcCa
  InspectFile 'TARGET_CA' $destCa
  $sourceDll=@()
  $destDll=@()
  try{$sourceDll=@(Get-ChildItem -LiteralPath $BootstrapTlsDir -Filter '*.dll' -ErrorAction Stop)}catch{'SOURCE_DLL_LIST=FAILED'}
  try{$destDll=@(Get-ChildItem -LiteralPath $bin -Filter '*.dll' -ErrorAction Stop)}catch{'TARGET_DLL_LIST=FAILED'}
  'SOURCE_DLL_COUNT='+$sourceDll.Count
  'TARGET_DLL_COUNT='+$destDll.Count
  $missingDll=0
  $differentDll=0
  foreach($item in $sourceDll){
    $dest=Join-Path $bin $item.Name
    if(-not [IO.File]::Exists($dest)){$missingDll++}
    elseif($item.Length -ne ([IO.FileInfo]$dest).Length){$differentDll++}
  }
  'TLS_DLL_MISSING_COUNT='+$missingDll
  'TLS_DLL_SIZE_MISMATCH_COUNT='+$differentDll
  if([IO.File]::Exists($srcExe) -and [IO.File]::Exists($destExe)){
    'CURL_COPY_HASH_MATCH='+((Sha $srcExe) -eq (Sha $destExe))
  }
  if([IO.File]::Exists($srcCa) -and [IO.File]::Exists($destCa)){
    'CA_COPY_HASH_MATCH='+((Sha $srcCa) -eq (Sha $destCa))
  }
  ExecVersion 'SOURCE_CURL' $srcExe
  ExecVersion 'TARGET_CURL' $destExe
  $zip=Join-Path $root 'staging\sqlite-tools-win32-x86-3430200.zip'
  'SQLITE_ZIP_PRESENT='+[IO.File]::Exists($zip)
  $sqlite=Join-Path $bin 'sqlite3.exe'
  'SQLITE_EXE_PRESENT='+[IO.File]::Exists($sqlite)
  'COLLECTOR_DB_PRESENT='+[IO.File]::Exists((Join-Path $root 'data\customers.db'))
  'COLLECTOR_TASK_CREATED=NO_AS_REPORTED'
  'FILES_WRITTEN=NO'
  'ACL_CHANGES=NO'
  'TASK_CHANGES=NO'
  'ONEC_CALLS=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_TLS_INSTALL_BLOCK_DIAGNOSTIC'
}catch{
  'RESULT=FAIL;STAGE=SRV_TLS_INSTALL_BLOCK_DIAGNOSTIC;GATE=READ_ONLY_DIAG_FAILED'
  'EXCEPTION_TYPE='+$_.Exception.GetType().Name
}finally{
  'INSTALL_RETRY=NO'
}

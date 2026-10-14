#requires -version 2
# Stage only. Windows 2008 R2 / PS2. Copies bounded probe agent to ProgramData.
# No task activation/deactivation, no VPS/1C/IIS changes.
param(
  [Parameter(Mandatory=$true)][string]$ExpectedComputerName,
  [Parameter(Mandatory=$true)][string]$ExpectedAccount,
  [Parameter(Mandatory=$true)][string]$CurlExe,
  [Parameter(Mandatory=$true)][string]$CaBundle
)
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$old=Join-Path $env:LOCALAPPDATA 'MspOnecAgent'
$created=$false
$ptr=[IntPtr]::Zero
$clear=$null
$plainBytes=$null
$sealed=$null
function Gate([string]$stage) {
  Write-Output ('RESULT=FAIL;STAGE=SYSTEM_PREPARE;GATE='+$stage)
  exit 1
}
function AllowAcl([string]$folder,[bool]$writeState) {
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  $service='*S-1-5-19:(OI)(CI)RX'
  if ($writeState) { $service='*S-1-5-19:(OI)(CI)M' }
  & $ic $folder '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' $service | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'ACL_SETUP_FAILED' }
}
function VerifyCopy([string]$from,[string]$to) {
  $sha=[Security.Cryptography.SHA256]::Create()
  try {
    $a=[IO.File]::ReadAllBytes($from); $b=[IO.File]::ReadAllBytes($to)
    $ha=[BitConverter]::ToString($sha.ComputeHash($a))
    $hb=[BitConverter]::ToString($sha.ComputeHash($b))
    if ($ha -ne $hb) { throw 'COPY_HASH_MISMATCH' }
  } finally { $sha.Dispose() }
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  if ([Security.Principal.WindowsIdentity]::GetCurrent().Name -ne $ExpectedAccount) {
    throw 'WRONG_ACCOUNT'
  }
  $ident=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $ident.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  if ([Environment]::OSVersion.Version.Major -ne 6 -or
      [Environment]::OSVersion.Version.Minor -ne 1) { throw 'WRONG_OS' }
  if (Test-Path -LiteralPath $root) { throw 'SYSTEM_STAGE_ALREADY_EXISTS' }
  $agentSource=Join-Path $old 'bin\onec-system-probe-poll.ps1'
  $legacy=Join-Path $old 'bin\onec-probe-poll.ps1'
  $tokenSource=Join-Path $old 'agent-token.dpapi'
  $endpointSource=Join-Path $old 'endpoint.txt'
  foreach($f in @($agentSource,$legacy,$tokenSource,$endpointSource,$CurlExe,$CaBundle)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw 'REQUIRED_FILE_MISSING' }
  }
  $address=[IO.File]::ReadAllText($endpointSource,[Text.Encoding]::ASCII).Trim()
  if ($address -notmatch '^https://[a-z0-9-]+\.tail[a-z0-9-]+\.ts\.net:8443$') {
    throw 'INVALID_ENDPOINT'
  }
  $script=[IO.File]::ReadAllText($agentSource,[Text.Encoding]::UTF8)
  if (-not $script.StartsWith('#requires -version 2') -or
      -not $script.Contains("S-1-5-19") -or
      -not $script.Contains('DataProtectionScope]::LocalMachine')) {
    throw 'INVALID_SYSTEM_SCRIPT'
  }
  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $tasks=$service.GetFolder('\')
  $legacyTask=$tasks.GetTask('MspOnecHttpsAgentProbe')
  if ($null -eq $legacyTask -or -not $legacyTask.Enabled) { throw 'LEGACY_TASK_NOT_RUNNING' }
  try {
    $existing=$tasks.GetTask('MspOnecHttpsAgentSystem')
    if ($null -ne $existing) { throw 'NEW_TASK_ALREADY_EXISTS' }
  } catch {
    if ($_.Exception.Message -eq 'NEW_TASK_ALREADY_EXISTS') { throw }
  }
  $cipher=[IO.File]::ReadAllText($tokenSource,[Text.Encoding]::UTF8).Trim()
  $secure=ConvertTo-SecureString -String $cipher
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $clear=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  if ($clear -notmatch '^[A-Za-z0-9_-]{32,128}$') { throw 'BAD_OLD_TOKEN' }
  [byte[]]$plainBytes=[Text.Encoding]::ASCII.GetBytes($clear)
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $sealed=[Security.Cryptography.ProtectedData]::Protect(
    $plainBytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  [void](New-Item -ItemType Directory -Path $root)
  $created=$true
  AllowAcl $root $false
  foreach($child in @('bin','config','secrets','state')) {
    $dir=Join-Path $root $child
    [void](New-Item -ItemType Directory -Path $dir)
    AllowAcl $dir ($child -eq 'state')
  }
  $bin=Join-Path $root 'bin'
  $sys=Join-Path $bin 'onec-system-probe-poll.ps1'
  Copy-Item -LiteralPath $agentSource -Destination $sys
  VerifyCopy $agentSource $sys
  $curlDst=Join-Path $bin 'curl.exe'
  $caDst=Join-Path $bin 'curl-ca-bundle.crt'
  Copy-Item -LiteralPath $CurlExe -Destination $curlDst
  VerifyCopy $CurlExe $curlDst
  Copy-Item -LiteralPath $CaBundle -Destination $caDst
  VerifyCopy $CaBundle $caDst
  $curlSourceDir=Split-Path -Parent $CurlExe
  foreach($dll in @(Get-ChildItem -LiteralPath $curlSourceDir -Filter '*.dll' -ErrorAction Stop)) {
    $dllDst=Join-Path $bin $dll.Name
    Copy-Item -LiteralPath $dll.FullName -Destination $dllDst
    VerifyCopy $dll.FullName $dllDst
  }
  # Reset file ACLs to the separately restricted destination directory defaults.
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  foreach($file in @(Get-ChildItem -LiteralPath $bin | Where-Object { -not $_.PSIsContainer })) {
    & $ic $file.FullName '/reset' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'FILE_ACL_FAILURE' }
  }
  [IO.File]::WriteAllText((Join-Path (Join-Path $root 'config') 'endpoint.txt'),$address,[Text.Encoding]::ASCII)
  [IO.File]::WriteAllBytes((Join-Path (Join-Path $root 'secrets') 'agent-token.machine.dpapi'),$sealed)
  & $curlDst -q --version | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'SYSTEM_CURL_START_FAILED' }
  Write-Output 'ONEC_LOCAL_SERVICE_STAGE'
  Write-Output 'SYSTEM_PROGRAMDATA_FILES=PASS'
  Write-Output 'SOURCE_SHA256_COPY_VERIFIED=PASS'
  Write-Output 'OLD_DPAPI_TO_MACHINE_DPAPI=PASS'
  Write-Output 'LOCAL_SERVICE_FILE_ACL=STAGED'
  Write-Output 'SYSTEM_CURL_START=PASS'
  Write-Output 'PERSONAL_AGENT_TASK=UNCHANGED'
  Write-Output 'NEW_SYSTEM_TASK=NOT_CREATED'
  Write-Output 'SYSTEM_AGENT_EXECUTION=NOT_TESTED'
  Write-Output 'RESULT=PASS'
} catch {
  $reason=$_.Exception.Message
  $allowed=@('WRONG_MACHINE','WRONG_ACCOUNT','ADMIN_REQUIRED','WRONG_OS',
    'SYSTEM_STAGE_ALREADY_EXISTS','REQUIRED_FILE_MISSING','INVALID_ENDPOINT',
    'INVALID_SYSTEM_SCRIPT','LEGACY_TASK_NOT_RUNNING','NEW_TASK_ALREADY_EXISTS',
    'BAD_OLD_TOKEN','ACL_SETUP_FAILED','COPY_HASH_MISMATCH','FILE_ACL_FAILURE',
    'SYSTEM_CURL_START_FAILED')
  if ($allowed -notcontains $reason) { $reason='SYSTEM_STAGE_FAILURE' }
  Write-Output ('RESULT=FAIL;STAGE=SYSTEM_PREPARE;GATE='+$reason)
  if ($created) {
    try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop } catch {}
  }
  exit 1
} finally {
  $clear=$null
  if ($null -ne $plainBytes) { [Array]::Clear($plainBytes,0,$plainBytes.Length) }
  if ($null -ne $sealed) { [Array]::Clear($sealed,0,$sealed.Length) }
  if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  if ($null -ne $secure) { $secure.Dispose() }
}

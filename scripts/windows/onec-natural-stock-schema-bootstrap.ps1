#requires -version 2
# Pinned staging for an administrator-authorized one-shot, NewBase GET only.
# Does not add remote shell execution to the HTTPS LocalService poller.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='IDENTITY'
$commit='3909889c4aa177d834961d26d13af6541a20f3d4'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$curl=Join-Path (Join-Path $root 'bin') 'curl.exe'
$ca=Join-Path (Join-Path $root 'bin') 'curl-ca-bundle.crt'
$destination=Join-Path $env:TEMP 'OnecNaturalSchema_20261015'
$expected=@{
  'onec-natural-stock-schema-preflight.ps1'='c82e433205ee3a8353165381c33a7a2f43892b50';
  'onec-natural-stock-schema-runner.ps1'='079e7fe7760cd9a209c5973f91a3c5c75b87d6e3';
  'onec-natural-stock-schema-once.ps1'='59a92118e6bcd7325e4c8f87a8d960d709c90254'
}
function BlobHash([string]$path) {
  [byte[]]$bytes=[IO.File]::ReadAllBytes($path)
  [byte[]]$head=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0))
  $stream=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $stream.Write($head,0,$head.Length)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
  } finally { $sha.Clear(); $stream.Close() }
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_HOST' }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_POWERSHELL' }
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  if (-not (Test-Path -LiteralPath $curl -PathType Leaf) -or
      -not (Test-Path -LiteralPath $ca -PathType Leaf)) { throw 'APPROVED_CURL_MISSING' }
  if (Test-Path -LiteralPath $destination) { throw 'STAGING_ALREADY_PRESENT' }
  $phase='PINNED_DOWNLOAD'
  New-Item -ItemType Directory -Path $destination -ErrorAction Stop | Out-Null
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/'+$commit+'/scripts/windows/'
  foreach($filename in @('onec-natural-stock-schema-preflight.ps1',
        'onec-natural-stock-schema-runner.ps1','onec-natural-stock-schema-once.ps1')) {
    $target=Join-Path $destination $filename
    $arguments=@('-q','--fail','--silent','--show-error','--noproxy','*',
       '--tlsv1.2','--tls-max','1.2','--proto','=https','--max-redirs','0',
       '--cacert',$ca,'--connect-timeout','15','--max-time','40',
       '--output',$target,($url+$filename))
    & $curl @arguments
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $target -PathType Leaf) -or
        (BlobHash $target) -ne $expected[$filename]) {
      throw 'PINNED_FILE_DOWNLOAD_FAILED'
    }
  }
  $phase='PINNED_ADMIN_ONE_SHOT'
  $installer=Join-Path $destination 'onec-natural-stock-schema-once.ps1'
  & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer -ExpectedComputerName $ExpectedComputerName
  if ($LASTEXITCODE -ne 0) { throw 'ONE_SHOT_FAILED' }
  Write-Output 'ONEC_NATURAL_STOCK_BOOTSTRAP'
  Write-Output 'PINNED_SOURCE_COMMIT=VERIFIED'
  Write-Output 'ONE_SHOT_COMMAND=EXECUTED'
  Write-Output 'OPERATIONAL_AGENT_MODIFIED=NO'
  Write-Output 'RESULT=PASS'
  exit 0
} catch {
  $allowed=@('WRONG_HOST','WRONG_POWERSHELL','ADMIN_REQUIRED',
    'APPROVED_CURL_MISSING','STAGING_ALREADY_PRESENT',
    'PINNED_FILE_DOWNLOAD_FAILED','ONE_SHOT_FAILED')
  $reason=$_.Exception.Message
  if ($allowed -notcontains $reason) { $reason='BOOTSTRAP_FAILURE' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  exit 1
}

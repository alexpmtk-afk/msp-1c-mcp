#requires -version 2
# System task entrypoint. Bootstrap is intentionally SAFE_IDLE and has no network.
param([string]$RootDir = 'C:\ProgramData\MspBitrix24Bridge')
$ErrorActionPreference='Stop'
function Fail([string]$Reason) {
  Write-Output ('RESULT=FAIL;COMPONENT=MSP_BITRIX24_BRIDGE;GATE='+$Reason)
  exit 1
}
try {
  $expected=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
  if ($RootDir -ne $expected) { Fail 'ROOT_MISMATCH' }
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  if ($id.User.Value -ne 'S-1-5-19') { Fail 'NOT_LOCAL_SERVICE' }
  $cfg=Join-Path $RootDir 'config\bridge.ini'
  $state=Join-Path $RootDir 'state'
  if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { Fail 'POLICY_MISSING' }
  if (-not (Test-Path -LiteralPath $state -PathType Container)) { Fail 'STATE_MISSING' }
  $policy=@{}
  foreach($line in [IO.File]::ReadAllLines($cfg,[Text.Encoding]::ASCII)) {
    $t=$line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t -notmatch '^(ACTIVE|CUSTOMERS_READ|PRODUCTS_READ|INVOICES_WRITE)=([01])$') { Fail 'POLICY_INVALID' }
    if ($policy.ContainsKey($Matches[1])) { Fail 'POLICY_DUPLICATE' }
    $policy[$Matches[1]]=$Matches[2]
  }
  foreach($key in @('ACTIVE','CUSTOMERS_READ','PRODUCTS_READ','INVOICES_WRITE')) {
    if (-not $policy.ContainsKey($key)) { Fail 'POLICY_INCOMPLETE' }
  }
  # Fail closed: this bootstrap does not contain the future data sync engine.
  if ($policy['ACTIVE'] -ne '0' -or $policy['CUSTOMERS_READ'] -ne '0' -or
      $policy['PRODUCTS_READ'] -ne '0' -or $policy['INVOICES_WRITE'] -ne '0') {
    Fail 'CAPABILITY_NOT_IMPLEMENTED'
  }
  $mutex=New-Object System.Threading.Mutex -ArgumentList @($false,'Local\MspBitrix24Bridge')
  $locked=$false
  try {
    $locked=$mutex.WaitOne(0,$false)
    if (-not $locked) { Fail 'ALREADY_RUNNING' }
    $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $tmp=Join-Path $state 'status.tmp'
    $dst=Join-Path $state 'status.txt'
    [IO.File]::WriteAllText($tmp,('UTC='+$stamp+';STATUS=SAFE_IDLE;IDENTITY=LOCAL_SERVICE;CUSTOMERS_SYNC=OFF;WRITES=OFF'),[Text.Encoding]::ASCII)
    if (Test-Path $dst) { Remove-Item -LiteralPath $dst -Force }
    Move-Item -LiteralPath $tmp -Destination $dst -Force
    Write-Output 'RESULT=PASS;COMPONENT=MSP_BITRIX24_BRIDGE;STATUS=SAFE_IDLE;CUSTOMERS_SYNC=OFF;WRITES=OFF'
  } finally {
    if ($locked) { [void]$mutex.ReleaseMutex() }
    $mutex.Close()
  }
} catch {
  Fail 'LOCAL_RUNTIME_ERROR'
}

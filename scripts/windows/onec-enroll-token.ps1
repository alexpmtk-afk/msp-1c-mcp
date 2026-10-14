#requires -version 2
# Run interactively on SRV as the same user that will run the poller.
# Do not paste the secret into chat, scripts or command history.
param([string]$StateDir = (Join-Path $env:LOCALAPPDATA 'MspOnecAgent'))
$ErrorActionPreference='Stop'
try {
  if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) {
    [void](New-Item -Path $StateDir -ItemType Directory)
  }
  $account=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  $icacls=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $icacls $StateDir '/inheritance:r' '/grant:r' ($account+':(OI)(CI)F') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'ACL_FAILED' }
  $destination=Join-Path $StateDir 'agent-token.dpapi'
  $endpointFile=Join-Path $StateDir 'endpoint.txt'
  if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $endpointFile)) { throw 'ALREADY_ENROLLED' }
  $endpoint=Read-Host 'Approved HTTPS Funnel URL ending with :8443'
  if ($endpoint -notmatch '^https://[a-z0-9-]+\.tail[a-z0-9-]+\.ts\.net:8443 'Paste the agent token from the private VPS root console (hidden input)' -AsSecureString
  if ($null -eq $secret -or $secret.Length -lt 32 -or $secret.Length -gt 128) { throw 'INVALID_TOKEN_LENGTH' }
  $protected=$secret | ConvertFrom-SecureString
  [IO.File]::WriteAllText($destination,$protected,[Text.Encoding]::UTF8)
  try { [IO.File]::WriteAllText($endpointFile,$endpoint,[Text.Encoding]::ASCII) }
  catch { Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue; throw }
  $protected=$null
  $secret.Dispose()
  Write-Output 'RESULT=PASS;STAGE=LOCAL_DPAPI_ENROLLED;SECRET_EXPORTED=NO'
} catch {
  Write-Output 'RESULT=FAIL;STAGE=LOCAL_DPAPI_ENROLLMENT'
  exit 1
}
) { throw 'INVALID_ENDPOINT' }
  $secret=Read-Host 'Paste the agent token from the private VPS root console (hidden input)' -AsSecureString
  if ($null -eq $secret -or $secret.Length -lt 32 -or $secret.Length -gt 128) { throw 'INVALID_TOKEN_LENGTH' }
  $protected=$secret | ConvertFrom-SecureString
  [IO.File]::WriteAllText($destination,$protected,[Text.Encoding]::UTF8)
  $protected=$null
  $secret.Dispose()
  Write-Output 'RESULT=PASS;STAGE=LOCAL_DPAPI_ENROLLED;SECRET_EXPORTED=NO'
} catch {
  Write-Output 'RESULT=FAIL;STAGE=LOCAL_DPAPI_ENROLLMENT'
  exit 1
}

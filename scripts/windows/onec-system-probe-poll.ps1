#requires -version 2
# LocalService fixed-operations poller: probe or sandbox OData Balance GET. No arbitrary commands.
# NEVER run with the personal user-scoped token or personal state directory.
# PowerShell 2.0 / Windows Server 2008 R2. TLS handled by approved portable curl.
param(
  [Parameter(Mandatory=$true)][string]$CurlExe,
  [Parameter(Mandatory=$true)][string]$CaBundle,
  [string]$RootDir = (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent')
)
$ErrorActionPreference='Stop'
$StateDir=Join-Path $RootDir 'state'
$EndpointFile=Join-Path (Join-Path $RootDir 'config') 'endpoint.txt'
$Endpoint=''
$TokenFile=Join-Path (Join-Path $RootDir 'secrets') 'agent-token.machine.dpapi'
function Health([string]$Mode) {
  try {
    if (Test-Path -LiteralPath $StateDir -PathType Container) {
      $msg=('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS='+$Mode)
      [IO.File]::WriteAllText((Join-Path $StateDir 'last-status.txt'),$msg,[Text.Encoding]::ASCII)
    }
  } catch {}
}
function StopSafe([string]$Reason) {
  Health 'FAIL'
  Write-Output ('RESULT=FAIL;STAGE=SYSTEM_AGENT;GATE='+$Reason)
  exit 1
}
function ReadLocalToken {
  [byte[]]$enc=[IO.File]::ReadAllBytes($TokenFile)
  [byte[]]$plainBytes=$null
  try {
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $plainBytes=[Security.Cryptography.ProtectedData]::Unprotect(
      $enc,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
    $plain=[Text.Encoding]::ASCII.GetString($plainBytes)
    if ($plain -notmatch '^[A-Za-z0-9_-]{32,128}$') { throw 'INVALID_TOKEN' }
    return $plain
  } finally {
    if ($null -ne $plainBytes) { [Array]::Clear($plainBytes,0,$plainBytes.Length) }
    if ($null -ne $enc) { [Array]::Clear($enc,0,$enc.Length) }
  }
}
function AgentRequest([string]$Method,[string]$Path,[string]$Payload) {
  if (($Method -eq 'GET' -and $Path -ne '/v1/agent/poll') -or
      ($Method -eq 'POST' -and $Path -ne '/v1/agent/result') -or
      ($Method -ne 'GET' -and $Method -ne 'POST')) { throw 'PATH_NOT_ALLOWED' }
  $configFile=Join-Path $StateDir ('curl-'+[Guid]::NewGuid().ToString('N')+'.cfg')
  $replyFile=Join-Path $StateDir ('body-'+[Guid]::NewGuid().ToString('N')+'.txt')
  try {
    $token=ReadLocalToken
    [IO.File]::WriteAllText($configFile,('header = "Authorization: Bearer '+$token+'"'+[Environment]::NewLine),[Text.Encoding]::ASCII)
    $token=$null
    $args=@('-q','--config',$configFile,'--silent','--show-error','--fail',
            '--proto','=https','--max-redirs','0',
            '--noproxy','*','--http1.1','--tlsv1.2','--tls-max','1.2',
            '--cacert',$CaBundle,'--connect-timeout','15','--max-time','45',
            '--output',$replyFile,'--request',$Method)
    if ($Method -eq 'POST') {
      if (-not (Test-Path -LiteralPath $Payload -PathType Leaf)) { throw 'MISSING_PAYLOAD' }
      $args+=@('--header','Content-Type: text/plain','--data-binary',('@'+$Payload))
    }
    $args+=@($Endpoint+$Path)
    & $CurlExe @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'CURL_FAILED' }
    if (-not (Test-Path -LiteralPath $replyFile -PathType Leaf)) { throw 'MISSING_REPLY' }
    $reply=[IO.File]::ReadAllText($replyFile,[Text.Encoding]::ASCII).Trim()
    if ($reply.Length -gt 256) { throw 'REPLY_TOO_LARGE' }
    return $reply
  } finally {
    Remove-Item -LiteralPath $configFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $replyFile -Force -ErrorAction SilentlyContinue
  }
}
try {
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  if ($identity.User.Value -ne 'S-1-5-19') { StopSafe 'NOT_LOCAL_SERVICE' }
  $canonical=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
  if ($RootDir -ne $canonical) { StopSafe 'WRONG_ROOT' }
  $bin=Join-Path $RootDir 'bin'
  if ($CurlExe -ne (Join-Path $bin 'curl.exe') -or
      $CaBundle -ne (Join-Path $bin 'curl-ca-bundle.crt')) { StopSafe 'UNTRUSTED_BINARY_PATH' }
  if (-not (Test-Path -LiteralPath $CurlExe -PathType Leaf)) { StopSafe 'CURL_MISSING' }
  if (-not (Test-Path -LiteralPath $CaBundle -PathType Leaf)) { StopSafe 'CA_MISSING' }
  if (-not (Test-Path -LiteralPath $TokenFile -PathType Leaf)) { StopSafe 'TOKEN_NOT_ENROLLED' }
  if (-not (Test-Path -LiteralPath $StateDir -PathType Container)) { StopSafe 'STATE_MISSING' }
  if (-not (Test-Path -LiteralPath $EndpointFile -PathType Leaf)) { StopSafe 'ENDPOINT_NOT_ENROLLED' }
  $Endpoint=[IO.File]::ReadAllText($EndpointFile,[Text.Encoding]::ASCII).Trim()
  if ($Endpoint -notmatch '^https://[a-z0-9-]+\.tail[a-z0-9-]+\.ts\.net:8443$') { StopSafe 'INVALID_HTTPS_ENDPOINT' }
  # One agent instance per Windows logon; prevent overlapping scheduled jobs.
  $mutex=New-Object System.Threading.Mutex -ArgumentList @($false,'Local\MspOnecAgentPoll')
  $owned=$false
  try {
    $owned=$mutex.WaitOne(0,$false)
    if (-not $owned) { StopSafe 'ALREADY_RUNNING' }
    $pending=@(Get-ChildItem -LiteralPath $StateDir -Filter 'result-*.txt' -ErrorAction SilentlyContinue)
    foreach($file in $pending) {
      $payload=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::ASCII).Trim()
      if (-not ($payload -match '^RESULT\|([0-9a-f]{32})\|([0-9a-f]{32})\|(PASS|FAIL)\|(SRV_ALIVE|CLIENT_ERROR|STOCK_Q_-?[0-9]{1,9}(?:\.[0-9]{1,3})?|ODATA_[A-Z_]+)$')) {
        throw 'INVALID_PENDING_RESULT'
      }
      $jid=$Matches[1]
      $ack=AgentRequest 'POST' '/v1/agent/result' $file.FullName
      if ($ack -ne ('RECORDED|'+$jid)) { throw 'BAD_PENDING_ACK' }
      Remove-Item -LiteralPath $file.FullName -Force
      Write-Output 'PENDING_RESULT_RECOVERED=YES'
    }
    $task=AgentRequest 'GET' '/v1/agent/poll' $null
    if ($task -eq 'EMPTY') { Health 'POLL_OK'; Write-Output 'RESULT=PASS;STAGE=AUTHENTICATED_EMPTY'; exit 0 }
    if ($task -notmatch '^TASK\|([0-9a-f]{32})\|(probe|odata_balance)\|([0-9a-f]{32})$') {
      throw 'UNRECOGNIZED_TASK'
    }
    $jid=$Matches[1];$operation=$Matches[2];$lease=$Matches[3]
    $marker=Join-Path $StateDir ('task-'+$jid+'.txt')
    if (Test-Path -LiteralPath $marker) {
      $old=[IO.File]::ReadAllText($marker,[Text.Encoding]::ASCII).Trim()
      if ($old -ne $lease) { throw 'REPLAY_LEASE_MISMATCH' }
    } else {
      [IO.File]::WriteAllText($marker,$lease,[Text.Encoding]::ASCII)
    }
    $result=Join-Path $StateDir ('result-'+$jid+'.txt')
    $status='PASS'; $reason='SRV_ALIVE'
    if ($operation -eq 'odata_balance') {
      $helper=Join-Path $bin 'onec-system-odata-balance.ps1'
      if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { $status='FAIL';$reason='ODATA_HELPER_MISSING' }
      else {
        $value=& (Join-Path $PSHOME 'powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper
        if ($LASTEXITCODE -eq 0 -and $value -match '^STOCK_Q_-?[0-9]{1,9}(?:\.[0-9]{1,3})?
    $ack=AgentRequest 'POST' '/v1/agent/result' $result
    if ($ack -ne ('RECORDED|'+$jid)) { throw 'ACK_MISMATCH' }
    Remove-Item -LiteralPath $result -Force
    Health 'PROBE_ACK'
    Write-Output ('RESULT=PASS;STAGE=PROBE_ACK;TASK_ID='+$jid)
  } finally {
    if ($owned) { [void]$mutex.ReleaseMutex() }
    $mutex.Close()
  }
} catch {
  StopSafe 'GENERAL_FAILURE'
}
) { $reason=$value }
        else { $status='FAIL';$reason='ODATA_READ_FAILED' }
      }
    }
    [IO.File]::WriteAllText($result,('RESULT|'+$jid+'|'+$lease+'|'+$status+'|'+$reason),[Text.Encoding]::ASCII)
    $ack=AgentRequest 'POST' '/v1/agent/result' $result
    if ($ack -ne ('RECORDED|'+$jid)) { throw 'ACK_MISMATCH' }
    Remove-Item -LiteralPath $result -Force
    Health 'PROBE_ACK'
    Write-Output ('RESULT=PASS;STAGE=PROBE_ACK;TASK_ID='+$jid)
  } finally {
    if ($owned) { [void]$mutex.ReleaseMutex() }
    $mutex.Close()
  }
} catch {
  StopSafe 'GENERAL_FAILURE'
}

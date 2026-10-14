#requires -version 2
# One-shot, probe-only HTTPS agent. No 1C/COM/OData operations or arbitrary commands.
# PowerShell 2.0 / Windows Server 2008 R2. TLS handled by approved portable curl.
param(
  [Parameter(Mandatory=$true)][string]$CurlExe,
  [Parameter(Mandatory=$true)][string]$CaBundle,
  [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'MspOnecAgent')
)
$ErrorActionPreference='Stop'
$Endpoint='https://vm-817589.tail76ae70.ts.net:8443'
$TokenFile=Join-Path $StateDir 'agent-token.dpapi'
function StopSafe([string]$Reason) {
  Write-Output ('RESULT=FAIL;STAGE=AGENT;GATE='+$Reason)
  exit 1
}
function PrivateDir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $Path)
  }
  $account=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  $icacls=Join-Path $env:WINDIR 'System32\icacls.exe'
  if (-not (Test-Path -LiteralPath $icacls)) { throw 'NO_ICACLS' }
  & $icacls $Path '/inheritance:r' '/grant:r' ($account+':(OI)(CI)F') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'ACL_FAILED' }
}
function ReadLocalToken {
  $encrypted=[IO.File]::ReadAllText($TokenFile,[Text.Encoding]::UTF8).Trim()
  $secure=ConvertTo-SecureString -String $encrypted
  $ptr=[IntPtr]::Zero
  try {
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    if ($plain -notmatch '^[A-Za-z0-9_-]{32,128}$') { throw 'INVALID_TOKEN' }
    return $plain
  } finally {
    if ($ptr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
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
  if (-not (Test-Path -LiteralPath $CurlExe -PathType Leaf)) { StopSafe 'CURL_MISSING' }
  if (-not (Test-Path -LiteralPath $CaBundle -PathType Leaf)) { StopSafe 'CA_MISSING' }
  if (-not (Test-Path -LiteralPath $TokenFile -PathType Leaf)) { StopSafe 'TOKEN_NOT_ENROLLED' }
  PrivateDir $StateDir
  # One agent instance per Windows logon; prevent overlapping scheduled jobs.
  $mutex=New-Object System.Threading.Mutex -ArgumentList @($false,'Local\MspOnecAgentPoll')
  $owned=$false
  try {
    $owned=$mutex.WaitOne(0,$false)
    if (-not $owned) { StopSafe 'ALREADY_RUNNING' }
    $pending=@(Get-ChildItem -LiteralPath $StateDir -Filter 'result-*.txt' -ErrorAction SilentlyContinue)
    foreach($file in $pending) {
      $payload=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::ASCII).Trim()
      if (-not ($payload -match '^RESULT\|([0-9a-f]{32})\|([0-9a-f]{32})\|(PASS|FAIL)\|(SRV_ALIVE|CLIENT_ERROR)
        throw 'INVALID_PENDING_RESULT'
      }
      $jid=$Matches[1]
      $ack=AgentRequest 'POST' '/v1/agent/result' $file.FullName
      if ($ack -ne ('RECORDED|'+$jid)) { throw 'BAD_PENDING_ACK' }
      Remove-Item -LiteralPath $file.FullName -Force
      Write-Output 'PENDING_RESULT_RECOVERED=YES'
    }
    $task=AgentRequest 'GET' '/v1/agent/poll' $null
    if ($task -eq 'EMPTY') { Write-Output 'RESULT=PASS;STAGE=AUTHENTICATED_EMPTY'; exit 0 }
    if ($task -notmatch '^TASK\|([0-9a-f]{32})\|probe\|([0-9a-f]{32})$') {
      throw 'UNRECOGNIZED_TASK'
    }
    $jid=$Matches[1];$lease=$Matches[2]
    $marker=Join-Path $StateDir ('task-'+$jid+'.txt')
    if (Test-Path -LiteralPath $marker) {
      $old=[IO.File]::ReadAllText($marker,[Text.Encoding]::ASCII).Trim()
      if ($old -ne $lease) { throw 'REPLAY_LEASE_MISMATCH' }
    } else {
      [IO.File]::WriteAllText($marker,$lease,[Text.Encoding]::ASCII)
    }
    $result=Join-Path $StateDir ('result-'+$jid+'.txt')
    [IO.File]::WriteAllText($result,('RESULT|'+$jid+'|'+$lease+'|PASS|SRV_ALIVE'),[Text.Encoding]::ASCII)
    $ack=AgentRequest 'POST' '/v1/agent/result' $result
    if ($ack -ne ('RECORDED|'+$jid)) { throw 'ACK_MISMATCH' }
    Remove-Item -LiteralPath $result -Force
    Write-Output ('RESULT=PASS;STAGE=PROBE_ACK;TASK_ID='+$jid)
  } finally {
    if ($owned) { [void]$mutex.ReleaseMutex() }
    $mutex.Close()
  }
} catch {
  StopSafe 'GENERAL_FAILURE'
}
)) {
        throw 'INVALID_PENDING_RESULT'
      }
      $jid=$Matches[1]
      $ack=AgentRequest 'POST' '/v1/agent/result' $file.FullName
      if ($ack -ne ('RECORDED|'+$jid)) { throw 'BAD_PENDING_ACK' }
      Remove-Item -LiteralPath $file.FullName -Force
      Write-Output 'PENDING_RESULT_RECOVERED=YES'
    }
    $task=AgentRequest 'GET' '/v1/agent/poll' $null
    if ($task -eq 'EMPTY') { Write-Output 'RESULT=PASS;STAGE=AUTHENTICATED_EMPTY'; exit 0 }
    if ($task -notmatch '^TASK\|([0-9a-f]{32})\|probe\|([0-9a-f]{32})$') {
      throw 'UNRECOGNIZED_TASK'
    }
    $jid=$Matches[1];$lease=$Matches[2]
    $marker=Join-Path $StateDir ('task-'+$jid+'.txt')
    if (Test-Path -LiteralPath $marker) {
      $old=[IO.File]::ReadAllText($marker,[Text.Encoding]::ASCII).Trim()
      if ($old -ne $lease) { throw 'REPLAY_LEASE_MISMATCH' }
    } else {
      [IO.File]::WriteAllText($marker,$lease,[Text.Encoding]::ASCII)
    }
    $result=Join-Path $StateDir ('result-'+$jid+'.txt')
    [IO.File]::WriteAllText($result,('RESULT|'+$jid+'|'+$lease+'|PASS|SRV_ALIVE'),[Text.Encoding]::ASCII)
    $ack=AgentRequest 'POST' '/v1/agent/result' $result
    if ($ack -ne ('RECORDED|'+$jid)) { throw 'ACK_MISMATCH' }
    Remove-Item -LiteralPath $result -Force
    Write-Output ('RESULT=PASS;STAGE=PROBE_ACK;TASK_ID='+$jid)
  } finally {
    if ($owned) { [void]$mutex.ReleaseMutex() }
    $mutex.Close()
  }
} catch {
  StopSafe 'GENERAL_FAILURE'
}

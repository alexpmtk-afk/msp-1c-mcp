#requires -version 2
# Fixed one-file diagnostic upgrade of existing LocalService 1C agent.
# No scheduler changes, no 1C access, no remote code execution.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$live=Join-Path $bin 'onec-system-probe-poll.ps1'
$helper=Join-Path $bin 'onec-system-odata-balance.ps1'
$source=Join-Path (Join-Path $env:TEMP 'OnecOdataReview_20261014') 'onec-system-probe-poll.ps1'
$staged=Join-Path $bin 'onec-system-probe-poll.ps1.diag-v2.candidate'
$state=Join-Path $root 'state\last-status.txt'
$oldSha='33bf4a688ca0686270534771a961ee06b50e434e'
$newSha='26c43ce97baaab395ec6e00d66834d7d60acf89c'
$helperSha='a177e9a622c136f72edff8a5eedd432b8a047a37'
$backup=''
$changed=$false
$accepted=$false
$phase='PREFLIGHT'
function Blob([string]$path) {
  [byte[]]$data=[IO.File]::ReadAllBytes($path)
  [byte[]]$head=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length+[char]0))
  $mem=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $mem.Write($head,0,$head.Length)
    $mem.Write($data,0,$data.Length)
    $mem.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($mem))).Replace('-','').ToLowerInvariant()
  } finally {
    $sha.Clear()
    $mem.Close()
  }
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  if ($PSVersionTable.PSVersion.Major -ne 2 -or
      [Environment]::OSVersion.Version.Major -ne 6 -or
      [Environment]::OSVersion.Version.Minor -ne 1) { throw 'WRONG_HOST' }
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ADMIN_REQUIRED' }
  $phase='VERIFY_TASKS'
  $service=New-Object -ComObject 'Schedule.Service'
  $service.Connect()
  $folder=$service.GetFolder('\')
  $task=$folder.GetTask('MspOnecHttpsAgentSystem')
  $legacy=$folder.GetTask('MspOnecHttpsAgentProbe')
  $def=$task.Definition
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList $def.Principal.UserId).Translate([Security.Principal.SecurityIdentifier]).Value
  $expectedArgs=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
    $live+'" -CurlExe "'+(Join-Path $bin 'curl.exe')+'" -CaBundle "'+
    (Join-Path $bin 'curl-ca-bundle.crt')+'"')
  if (-not $task.Enabled -or $def.Triggers.Count -ne 1 -or
      -not $def.Triggers.Item(1).Enabled -or
      $def.Actions.Count -ne 1 -or $def.Principal.LogonType -ne 5 -or
      $def.Principal.RunLevel -ne 0 -or $sid -ne 'S-1-5-19' -or
      $def.Actions.Item(1).Path -ne (Join-Path $PSHOME 'powershell.exe') -or
      $def.Actions.Item(1).Arguments -ne $expectedArgs -or $legacy.Enabled) {
    throw 'TASK_STATE_UNEXPECTED'
  }
  $phase='VERIFY_FILES'
  foreach($p in @($source,$live,$helper)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'SOURCE_MISSING' }
  }
  if (Test-Path -LiteralPath $staged) { throw 'CANDIDATE_ALREADY_EXISTS' }
  if ((Blob $source) -ne $newSha -or (Blob $helper) -ne $helperSha) {
    throw 'PINNED_SOURCE_MISMATCH'
  }
  if ((Blob $live) -ne $oldSha) { throw 'LIVE_HASH_UNEXPECTED' }
  $parseErrors=$null
  $text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
  $null=[System.Management.Automation.PSParser]::Tokenize($text,[ref]$parseErrors)
  if (($parseErrors -and $parseErrors.Count -gt 0) -or
      -not $text.StartsWith('#requires -version 2') -or
      -not $text.Contains('VERSION=ODATA_DIAG_V2') -or
      -not $text.Contains("'ODATA_AUTH_DENIED'")) {
    throw 'SOURCE_PARSE_OR_GUARD_FAILED'
  }
  $phase='STAGE'
  Copy-Item -LiteralPath $source -Destination $staged -ErrorAction Stop
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $staged '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (Blob $staged) -ne $newSha) {
    throw 'STAGED_FILE_MISMATCH'
  }
  $backup=Join-Path $bin ('onec-system-probe-poll.ps1.pre-diag-v2-'+
    [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+[Guid]::NewGuid().ToString('N')+'.bak')
  $phase='ATOMIC_SWAP'
  $startedUtc=[DateTime]::UtcNow
  $startedLocal=Get-Date
  [IO.File]::Replace($staged,$live,$backup)
  $changed=$true
  if ((Blob $live) -ne $newSha -or (Blob $backup) -ne $oldSha) {
    throw 'SWAP_HASH_MISMATCH'
  }
  $phase='VERIFY_SCHEDULED_HEARTBEAT'
  for($i=1;$i -le 75;$i++) {
    Start-Sleep -Seconds 2
    $current=$folder.GetTask('MspOnecHttpsAgentSystem')
    if (-not $current.Enabled -or -not $current.Definition.Triggers.Item(1).Enabled -or
        $folder.GetTask('MspOnecHttpsAgentProbe').Enabled) {
      throw 'SCHEDULER_CHANGED'
    }
    if (Test-Path -LiteralPath $state -PathType Leaf) {
      $stamp=Get-Item -LiteralPath $state
      if ($stamp.LastWriteTimeUtc -ge $startedUtc -and
          $current.LastRunTime -ge $startedLocal.AddSeconds(-2)) {
        $value=[IO.File]::ReadAllText($state,[Text.Encoding]::ASCII).Trim()
        if ($value -match '^UTC=[0-9TZ:-]+;STATUS=(POLL_OK|PROBE_ACK);VERSION=ODATA_DIAG_V2$') {
          $accepted=$true
          break
        }
        if ($value -match '^UTC=[0-9TZ:-]+;STATUS=FAIL;VERSION=ODATA_DIAG_V2$') {
          throw 'AGENT_HEARTBEAT_FAILED'
        }
      }
    }
  }
  if (-not $accepted) { throw 'HEARTBEAT_TIMEOUT' }
  Write-Output 'ONEC_ODATA_DIAGNOSTIC_AGENT_UPGRADE'
  Write-Output 'SOURCE_HASH=PASS'
  Write-Output 'OLD_AGENT_BACKUP=YES'
  Write-Output 'ATOMIC_REPLACEMENT=PASS'
  Write-Output 'SCHEDULED_HEARTBEAT=PASS'
  Write-Output 'TASKS_UNCHANGED=YES'
  Write-Output 'ODATA_READ=NOT_RETRIED'
  Write-Output 'RESULT=PASS'
} catch {
  $reason=$_.Exception.Message
  $known=@('WRONG_MACHINE','WRONG_HOST','ADMIN_REQUIRED','TASK_STATE_UNEXPECTED',
    'SOURCE_MISSING','CANDIDATE_ALREADY_EXISTS','PINNED_SOURCE_MISMATCH',
    'LIVE_HASH_UNEXPECTED','SOURCE_PARSE_OR_GUARD_FAILED','STAGED_FILE_MISMATCH',
    'SWAP_HASH_MISMATCH','SCHEDULER_CHANGED','AGENT_HEARTBEAT_FAILED','HEARTBEAT_TIMEOUT')
  if ($known -notcontains $reason) { $reason='UPGRADE_FAILED' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  if ($changed -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
    try {
      $rollback=Join-Path $bin ('onec-system-probe-poll.ps1.diag-rollback-'+[Guid]::NewGuid().ToString('N'))
      Copy-Item -LiteralPath $backup -Destination $rollback -ErrorAction Stop
      [IO.File]::Replace($rollback,$live,$null)
      if ((Blob $live) -eq $oldSha) {
        Write-Output 'OLD_AGENT_RESTORED=PASS'
      } else {
        Write-Output 'OLD_AGENT_RESTORED=NOT_CONFIRMED'
      }
    } catch { Write-Output 'OLD_AGENT_RESTORED=FAILED' }
  } else {
    Write-Output 'OLD_AGENT_NOT_REPLACED=YES'
  }
  exit 1
} finally {
  if (Test-Path -LiteralPath $staged) {
    Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
  }
}

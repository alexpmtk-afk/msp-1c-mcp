#requires -version 2
# Upgrade only two fixed LocalService scripts for bounded HTTP error classification.
# No scheduler edits, no extra 1C access, no changes to credentials or IIS.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$work=Join-Path $env:TEMP 'OnecOdataReview_20261014'
$agent=Join-Path $bin 'onec-system-probe-poll.ps1'
$helper=Join-Path $bin 'onec-system-odata-balance.ps1'
$agentSrc=Join-Path $work 'onec-system-probe-poll.ps1'
$helperSrc=Join-Path $work 'onec-system-odata-balance.ps1'
$agentCand=Join-Path $bin 'onec-system-probe-poll.ps1.httpdiag.candidate'
$helperCand=Join-Path $bin 'onec-system-odata-balance.ps1.httpdiag.candidate'
$health=Join-Path $root 'state\last-status.txt'
$oldAgent='26c43ce97baaab395ec6e00d66834d7d60acf89c'
$newAgent='4c41b8edf9d13f55152090760f360e51c808c71f'
$oldHelper='a177e9a622c136f72edff8a5eedd432b8a047a37'
$newHelper='93ea2671c6cd424f396ddc1cefd6400751843a7d'
$agentBackup=''
$helperBackup=''
$agentChanged=$false
$helperChanged=$false
$accepted=$false
$phase='PREFLIGHT'
function Blob([string]$path) {
  [byte[]]$bytes=[IO.File]::ReadAllBytes($path)
  [byte[]]$prefix=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0))
  $stream=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $stream.Write($prefix,0,$prefix.Length)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
  } finally {
    $sha.Clear()
    $stream.Close()
  }
}
function CheckParse([string]$path) {
  $text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
  $errors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize($text,[ref]$errors)
  if ($errors -and $errors.Count -gt 0) { throw 'SOURCE_PARSE_FAILED' }
  if (-not $text.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) {
    throw 'SOURCE_PS2_GUARD_MISSING'
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
  $phase='VERIFY_TASK'
  $scheduler=New-Object -ComObject 'Schedule.Service'
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $task=$folder.GetTask('MspOnecHttpsAgentSystem')
  $personal=$folder.GetTask('MspOnecHttpsAgentProbe')
  $def=$task.Definition
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList $def.Principal.UserId).Translate([Security.Principal.SecurityIdentifier]).Value
  $expectedArguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
    $agent+'" -CurlExe "'+(Join-Path $bin 'curl.exe')+'" -CaBundle "'+
    (Join-Path $bin 'curl-ca-bundle.crt')+'"')
  if (-not $task.Enabled -or $def.Triggers.Count -ne 1 -or
      -not $def.Triggers.Item(1).Enabled -or $def.Actions.Count -ne 1 -or
      $def.Principal.LogonType -ne 5 -or $def.Principal.RunLevel -ne 0 -or
      $sid -ne 'S-1-5-19' -or $personal.Enabled -or
      $def.Actions.Item(1).Path -ne (Join-Path $PSHOME 'powershell.exe') -or
      $def.Actions.Item(1).Arguments -ne $expectedArguments) {
    throw 'TASK_STATE_UNEXPECTED'
  }
  $phase='VERIFY_PINNED_INPUTS'
  foreach($file in @($agentSrc,$helperSrc,$agent,$helper)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'INPUT_MISSING' }
  }
  if ((Test-Path -LiteralPath $agentCand) -or (Test-Path -LiteralPath $helperCand)) {
    throw 'CANDIDATE_ALREADY_EXISTS'
  }
  if ((Blob $agent) -ne $oldAgent -or (Blob $helper) -ne $oldHelper) {
    throw 'LIVE_HASH_UNEXPECTED'
  }
  if ((Blob $agentSrc) -ne $newAgent -or (Blob $helperSrc) -ne $newHelper) {
    throw 'PINNED_SOURCE_MISMATCH'
  }
  CheckParse $agentSrc
  CheckParse $helperSrc
  if (-not [IO.File]::ReadAllText($agentSrc).Contains('VERSION=ODATA_DIAG_V3')) {
    throw 'AGENT_VERSION_MISSING'
  }
  $phase='STAGE_SCRIPTS'
  Copy-Item -LiteralPath $agentSrc -Destination $agentCand -ErrorAction Stop
  Copy-Item -LiteralPath $helperSrc -Destination $helperCand -ErrorAction Stop
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $agentCand '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'FILE_ACL_FAILED' }
  & $ic $helperCand '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'FILE_ACL_FAILED' }
  if ((Blob $agentCand) -ne $newAgent -or (Blob $helperCand) -ne $newHelper) {
    throw 'STAGED_HASH_MISMATCH'
  }
  $suffix=[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+[Guid]::NewGuid().ToString('N')
  $agentBackup=Join-Path $bin ('onec-system-probe-poll.ps1.pre-httpdiag-'+$suffix+'.bak')
  $helperBackup=Join-Path $bin ('onec-system-odata-balance.ps1.pre-httpdiag-'+$suffix+'.bak')
  $phase='ATOMIC_SWAP'
  $startedUtc=[DateTime]::UtcNow
  $startedLocal=Get-Date
  [IO.File]::Replace($helperCand,$helper,$helperBackup)
  $helperChanged=$true
  [IO.File]::Replace($agentCand,$agent,$agentBackup)
  $agentChanged=$true
  if ((Blob $agent) -ne $newAgent -or (Blob $helper) -ne $newHelper -or
      (Blob $agentBackup) -ne $oldAgent -or (Blob $helperBackup) -ne $oldHelper) {
    throw 'POST_SWAP_HASH_MISMATCH'
  }
  $phase='VERIFY_SCHEDULED_AGENT'
  for($i=1;$i -le 75;$i++) {
    Start-Sleep -Seconds 2
    $current=$folder.GetTask('MspOnecHttpsAgentSystem')
    if (-not $current.Enabled -or -not $current.Definition.Triggers.Item(1).Enabled -or
        $folder.GetTask('MspOnecHttpsAgentProbe').Enabled) {
      throw 'SCHEDULER_CHANGED'
    }
    if (Test-Path -LiteralPath $health -PathType Leaf) {
      $stamp=Get-Item -LiteralPath $health
      if ($stamp.LastWriteTimeUtc -ge $startedUtc -and
          $current.LastRunTime -ge $startedLocal.AddSeconds(-2)) {
        $line=[IO.File]::ReadAllText($health,[Text.Encoding]::ASCII).Trim()
        if ($line -match '^UTC=[0-9TZ:-]+;STATUS=(POLL_OK|PROBE_ACK);VERSION=ODATA_DIAG_V3$') {
          $accepted=$true
          break
        }
        if ($line -match '^UTC=[0-9TZ:-]+;STATUS=FAIL;VERSION=ODATA_DIAG_V3$') {
          throw 'AGENT_POLL_FAILED'
        }
      }
    }
  }
  if (-not $accepted) { throw 'SCHEDULED_HEARTBEAT_TIMEOUT' }
  Write-Output 'ONEC_ODATA_ERROR_CLASS_UPGRADE'
  Write-Output 'PINNED_HASHES=PASS'
  Write-Output 'BOTH_OLD_SCRIPTS_BACKED_UP=YES'
  Write-Output 'ATOMIC_REPLACEMENTS=PASS'
  Write-Output 'NEW_AGENT_SCHEDULED_HEARTBEAT=PASS'
  Write-Output 'TASKS_UNCHANGED=YES'
  Write-Output 'ODATA_READ=NOT_RETRIED'
  Write-Output 'RESULT=PASS'
} catch {
  $reason=$_.Exception.Message
  $allowed=@('WRONG_MACHINE','WRONG_HOST','ADMIN_REQUIRED','TASK_STATE_UNEXPECTED',
    'INPUT_MISSING','CANDIDATE_ALREADY_EXISTS','LIVE_HASH_UNEXPECTED',
    'PINNED_SOURCE_MISMATCH','SOURCE_PARSE_FAILED','SOURCE_PS2_GUARD_MISSING',
    'AGENT_VERSION_MISSING','FILE_ACL_FAILED','STAGED_HASH_MISMATCH',
    'POST_SWAP_HASH_MISMATCH','SCHEDULER_CHANGED','AGENT_POLL_FAILED',
    'SCHEDULED_HEARTBEAT_TIMEOUT')
  if ($allowed -notcontains $reason) { $reason='UPGRADE_FAILED' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  if ($agentChanged -and (Test-Path -LiteralPath $agentBackup -PathType Leaf)) {
    try {
      $restore=Join-Path $bin ('onec-system-probe-poll.ps1.restore-'+[Guid]::NewGuid().ToString('N'))
      Copy-Item -LiteralPath $agentBackup -Destination $restore -ErrorAction Stop
      [IO.File]::Replace($restore,$agent,$null)
      if ((Blob $agent) -eq $oldAgent) { Write-Output 'OLD_AGENT_RESTORED=PASS' }
      else { Write-Output 'OLD_AGENT_RESTORED=NOT_CONFIRMED' }
    } catch { Write-Output 'OLD_AGENT_RESTORED=FAILED' }
  } else {
    Write-Output 'AGENT_NOT_REPLACED=YES'
  }
  if ($helperChanged -and (Test-Path -LiteralPath $helperBackup -PathType Leaf)) {
    try {
      $restore=Join-Path $bin ('onec-system-odata-balance.ps1.restore-'+[Guid]::NewGuid().ToString('N'))
      Copy-Item -LiteralPath $helperBackup -Destination $restore -ErrorAction Stop
      [IO.File]::Replace($restore,$helper,$null)
      if ((Blob $helper) -eq $oldHelper) { Write-Output 'OLD_HELPER_RESTORED=PASS' }
      else { Write-Output 'OLD_HELPER_RESTORED=NOT_CONFIRMED' }
    } catch { Write-Output 'OLD_HELPER_RESTORED=FAILED' }
  } else {
    Write-Output 'HELPER_NOT_REPLACED=YES'
  }
  exit 1
} finally {
  foreach($candidate in @($agentCand,$helperCand)) {
    if (Test-Path -LiteralPath $candidate) {
      Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
    }
  }
}

#requires -version 2
# One-time atomic LocalService script upgrade. No task edits or 1C access.
# Keep old poller backup and restore it automatically if the new scheduled
# versioned heartbeat is not observed. Windows Server 2008 R2 / PowerShell 2.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PREFLIGHT'
$changed=$false
$helperAdded=$false
$accepted=$false
$backup=''
$agentExpected='b7e77b81cd017705c7c502edc22f7cb68cc31fd9'
$helperExpected='10d464d1b53b65208bae764c70e5d85d40413fae'
$oldExpected='4c41b8edf9d13f55152090760f360e51c808c71f'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$srcDir=Join-Path $env:TEMP 'OnecOdataReview_20261014'
$dest=Join-Path $bin 'onec-system-probe-poll.ps1'
$helper=Join-Path $bin 'onec-system-odata-pair-check.ps1'
$candidate=Join-Path $bin 'onec-system-probe-poll.ps1.candidate'
$srcAgent=Join-Path $srcDir 'onec-system-probe-poll.ps1'
$srcHelper=Join-Path $srcDir 'onec-system-odata-pair-check.ps1'
$health=Join-Path $state 'last-status.txt'
function GitBlob([string]$path) {
  [byte[]]$data=[IO.File]::ReadAllBytes($path)
  [byte[]]$head=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length+[char]0))
  $stream=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $stream.Write($head,0,$head.Length)
    $stream.Write($data,0,$data.Length)
    $stream.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
  } finally {
    $sha.Clear()
    $stream.Close()
  }
}
function ParsePS2([string]$path) {
  $text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
  $errors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize($text,[ref]$errors)
  if ($errors -and $errors.Count -gt 0) { throw 'PS2_PARSE_ERROR' }
  if (-not $text.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) {
    throw 'SOURCE_PS2_GUARD_MISSING'
  }
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_POWERSHELL' }
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  if ([Environment]::OSVersion.Version.Major -ne 6 -or
      [Environment]::OSVersion.Version.Minor -ne 1) { throw 'WRONG_OS' }
  $phase='CHECK_LIVE_TASK'
  $scheduler=New-Object -ComObject 'Schedule.Service'
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $task=$folder.GetTask('MspOnecHttpsAgentSystem')
  $personal=$folder.GetTask('MspOnecHttpsAgentProbe')
  $definition=$task.Definition
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList $definition.Principal.UserId).Translate([Security.Principal.SecurityIdentifier]).Value
  $expectedExe=Join-Path $PSHOME 'powershell.exe'
  $expectedArgs=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
      $dest+'" -CurlExe "'+(Join-Path $bin 'curl.exe')+'" -CaBundle "'+
      (Join-Path $bin 'curl-ca-bundle.crt')+'"')
  if (-not $task.Enabled -or -not $definition.Triggers.Item(1).Enabled -or
      $definition.Triggers.Count -ne 1 -or $definition.Actions.Count -ne 1 -or
      $sid -ne 'S-1-5-19' -or $definition.Principal.LogonType -ne 5 -or
      $definition.Principal.RunLevel -ne 0 -or $personal.Enabled -or
      $definition.Actions.Item(1).Path -ne $expectedExe -or
      $definition.Actions.Item(1).Arguments -ne $expectedArgs) {
    throw 'TASK_STATE_UNEXPECTED'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $root 'secrets\odata-readonly.machine.dpapi') -PathType Leaf) -or
      -not (Test-Path -LiteralPath (Join-Path $root 'secrets\agent-token.machine.dpapi') -PathType Leaf)) {
    throw 'CREDENTIAL_FILE_MISSING'
  }
  $phase='VERIFY_PINNED_INPUTS'
  foreach($p in @($srcAgent,$srcHelper,$dest)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'INPUT_MISSING' }
  }
  if (Test-Path -LiteralPath $helper) { throw 'HELPER_ALREADY_INSTALLED' }
  if (Test-Path -LiteralPath $candidate) { throw 'CANDIDATE_ALREADY_EXISTS' }
  if ((GitBlob $srcAgent) -ne $agentExpected -or
      (GitBlob $srcHelper) -ne $helperExpected) { throw 'PINNED_SOURCE_MISMATCH' }
  if ((GitBlob $dest) -ne $oldExpected) { throw 'LIVE_SOURCE_UNEXPECTED' }
  ParsePS2 $srcAgent
  ParsePS2 $srcHelper
  $phase='COPY_FIXED_GET_HELPER'
  Copy-Item -LiteralPath $srcHelper -Destination $helper -ErrorAction Stop
  $helperAdded=$true
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $helper '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (GitBlob $helper) -ne $helperExpected) {
    throw 'HELPER_COPY_ACL_FAILURE'
  }
  $phase='PREPARE_ATOMIC_REPLACEMENT'
  Copy-Item -LiteralPath $srcAgent -Destination $candidate -ErrorAction Stop
  & $ic $candidate '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (GitBlob $candidate) -ne $agentExpected) {
    throw 'CANDIDATE_COPY_ACL_FAILURE'
  }
  $backup=Join-Path $bin ('onec-system-probe-poll.ps1.backup-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+[Guid]::NewGuid().ToString('N')+'.ps1')
  $phase='ATOMIC_REPLACE'
  $startedUtc=[DateTime]::UtcNow
  $startedLocal=Get-Date
  [IO.File]::Replace($candidate,$dest,$backup)
  $changed=$true
  if ((GitBlob $dest) -ne $agentExpected -or (GitBlob $backup) -ne $oldExpected) {
    throw 'POST_REPLACE_HASH_MISMATCH'
  }
  $phase='WAIT_AUTOMATIC_LOCAL_SERVICE'
  for($i=1;$i -le 75;$i++) {
    Start-Sleep -Seconds 2
    $recent=$folder.GetTask('MspOnecHttpsAgentSystem')
    if (-not $recent.Enabled -or -not $recent.Definition.Triggers.Item(1).Enabled) {
      throw 'SYSTEM_TIMER_CHANGED'
    }
    if (Test-Path -LiteralPath $health -PathType Leaf) {
      $stamp=Get-Item -LiteralPath $health
      if ($stamp.LastWriteTimeUtc -ge $startedUtc -and
          $recent.LastRunTime -ge $startedLocal.AddSeconds(-2)) {
        $message=[IO.File]::ReadAllText($health,[Text.Encoding]::ASCII).Trim()
        if ($message -match '^UTC=[0-9TZ:-]+;STATUS=(POLL_OK|PROBE_ACK);VERSION=ODATA_PAIR_V1$') {
          $accepted=$true
          break
        }
        if ($message -match '^UTC=[0-9TZ:-]+;STATUS=FAIL;VERSION=ODATA_PAIR_V1$') {
          throw 'NEW_AGENT_POLL_FAILED'
        }
      }
    }
  }
  if (-not $accepted) { throw 'NEW_AGENT_HEARTBEAT_TIMEOUT' }
  Write-Output 'ONEC_ODATA_PAIR_AGENT_UPGRADE'
  Write-Output 'PINNED_SOURCE_HASHES=PASS'
  Write-Output 'OLD_AGENT_BACKUP=YES'
  Write-Output 'ATOMIC_REPLACEMENT=PASS'
  Write-Output 'NEW_AGENT_SCHEDULED_HEARTBEAT=PASS'
  Write-Output 'SYSTEM_TASK_UNCHANGED=YES'
  Write-Output 'PERSONAL_AGENT_DISABLED=YES'
  Write-Output 'ODATA_READ=NOT_YET_TESTED'
  Write-Output 'RESULT=PASS'
} catch {
  $allowed=@('WRONG_MACHINE','WRONG_POWERSHELL','ADMIN_REQUIRED','WRONG_OS','TASK_STATE_UNEXPECTED',
    'CREDENTIAL_FILE_MISSING','INPUT_MISSING','HELPER_ALREADY_INSTALLED','CANDIDATE_ALREADY_EXISTS',
    'PINNED_SOURCE_MISMATCH','LIVE_SOURCE_UNEXPECTED','PS2_PARSE_ERROR','SOURCE_PS2_GUARD_MISSING',
    'HELPER_COPY_ACL_FAILURE','CANDIDATE_COPY_ACL_FAILURE','POST_REPLACE_HASH_MISMATCH',
    'SYSTEM_TIMER_CHANGED','NEW_AGENT_POLL_FAILED','NEW_AGENT_HEARTBEAT_TIMEOUT')
  $reason=$_.Exception.Message
  if ($allowed -notcontains $reason) { $reason='UPGRADE_ERROR' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  if ($changed -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
    try {
      $rollback=Join-Path $bin ('onec-system-probe-poll.ps1.rollback-'+[Guid]::NewGuid().ToString('N'))
      Copy-Item -LiteralPath $backup -Destination $rollback -ErrorAction Stop
      [IO.File]::Replace($rollback,$dest,$null)
      if ((GitBlob $dest) -eq $oldExpected) {
        Write-Output 'OLD_AGENT_RESTORED=PASS'
      } else {
        Write-Output 'OLD_AGENT_RESTORED=NOT_CONFIRMED'
      }
    } catch { Write-Output 'OLD_AGENT_RESTORED=FAILED' }
  } else {
    Write-Output 'OLD_AGENT_NOT_REPLACED=YES'
  }
  if ($helperAdded) {
    Remove-Item -LiteralPath $helper -Force -ErrorAction SilentlyContinue
  }
  exit 1
} finally {
  if (Test-Path -LiteralPath $candidate) {
    Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
  }
}

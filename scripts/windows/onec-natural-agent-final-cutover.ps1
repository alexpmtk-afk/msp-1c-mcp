#requires -version 2
# One-time opt-in on SRV by an already authorized local administrator.
# The physical SRV LocalService V4 exact two-card read-only smoke MUST have passed.
# NO network fetch, 1C writes, task schedule changes or elevation.
# Atomic agent replace + verified original backup + rollback if heartbeat fails.
$ErrorActionPreference='Stop'
$stage='PREFLIGHT'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$oldAgent=Join-Path $bin 'onec-system-probe-poll.ps1'
$helper=Join-Path $bin 'onec-system-odata-natural.ps1'
$smoke=Join-Path $bin 'onec-natural-live-smoke-runner.ps1'
$json=Join-Path $bin 'onec-legacy-json.ps1'
$writer=Join-Path $bin 'onec-natural-stock-json-writer.ps1'
$receipt=Join-Path $state 'natural-stock-v4-card-smoke-result.txt'
$health=Join-Path $state 'last-status.txt'
$curl=Join-Path $bin 'curl.exe'
$ca=Join-Path $bin 'curl-ca-bundle.crt'
$previousAgent='c7ad87b2d6ec41b0124a083d1bdf3305f5aee71f'
$previousHelper='31e15a0dcd6a6c23a879a9d121f400344d4b9fac'
$previousSmoke='5aa96846681bd51441d2cbc5c25a3d5250506ad9'
$expectedAgent='006a0b618575b4ab3a00b54c2863a436841e00ed'
$expectedHelper='08c23d0d6316ba7ddf1fd3e0f62e3269314838c7'
$expectedJson='05a3939ed2b8eb28378b395fc8a1b52989b5c3d5'
$expectedWriter='981a2e1ec0404b4afc42f0e35432f7cfbcde8e8a'
$expectedSmoke='0282d46c2935777a72987c37c1e4533a243a5842'
$map=@(
  @('onec-natural-final-poller.ps1',$expectedAgent),
  @('onec-natural-final-odata.ps1',$expectedHelper),
  @('onec-natural-final-json.ps1',$expectedJson),
  @('onec-natural-final-writer.ps1',$expectedWriter),
  @('onec-natural-final-smoke.ps1',$expectedSmoke)
)
$folder=$null
$changedHelpers=$false
$changedAgent=$false
$backup=''
$working=''
$backupDir=Join-Path $env:TEMP 'MspOnecFinalNaturalCutoverBackup_20261015'
function GitBlob([string]$path) {
  [byte[]]$raw=[IO.File]::ReadAllBytes($path)
  [byte[]]$h=[Text.Encoding]::ASCII.GetBytes(('blob '+$raw.Length+[char]0))
  $mem=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $mem.Write($h,0,$h.Length);$mem.Write($raw,0,$raw.Length);$mem.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($mem))).Replace('-','').ToLowerInvariant()
  } finally { $mem.Close();$sha.Clear() }
}
function VerifySource([string]$file) {
  $bytes=[IO.File]::ReadAllBytes($file)
  if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or
      $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw 'PS2_UTF8_BOM_REQUIRED' }
  $source=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
  if (-not $source.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) {
    throw 'PS2_GUARD_MISSING'
  }
  $errors=$null
  $null=[Management.Automation.PSParser]::Tokenize($source,[ref]$errors)
  if ($errors -and $errors.Count -gt 0) { throw 'PS2_PARSE_FAILED' }
}
try {
  if ($env:COMPUTERNAME -cne 'SRV' -or $PSVersionTable.PSVersion.Major -ne 2 -or
      [Environment]::OSVersion.Version.Major -ne 6 -or
      [Environment]::OSVersion.Version.Minor -ne 1) {
    throw 'WRONG_HOST_OR_POWERSHELL'
  }
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  foreach($dir in @($bin,$state)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw 'AGENT_DIRECTORY_MISSING' }
  }
  foreach($file in @($oldAgent,$helper,$smoke,$curl,$ca,$receipt,$health)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'REQUIRED_FILE_MISSING' }
  }
  if ((GitBlob $oldAgent) -ne $previousAgent -or
      (GitBlob $helper) -ne $previousHelper -or
      (GitBlob $smoke) -ne $previousSmoke) { throw 'OLD_AGENT_STATE_CHANGED' }
  if (Test-Path -LiteralPath $json -PathType Leaf) { throw 'JSON_ALREADY_INSTALLED' }
  if (Test-Path -LiteralPath $writer -PathType Leaf) { throw 'WRITER_ALREADY_INSTALLED' }
  if (Test-Path -LiteralPath $backupDir) { throw 'CUTOVER_STAGE_ALREADY_EXISTS' }
  $v4Expected=@('STAGE=COMPLETED','REASON=NONE','ERROR_TYPE=NONE','RESULT=PASS') -join [Environment]::NewLine
  $v4Actual=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
  if ($v4Actual -cne $v4Expected) { throw 'REAL_LOCAL_SERVICE_V4_SMOKE_NOT_ACCEPTED' }

  $stage='VERIFY_PREFETCHED_SOURCES'
  foreach($pair in $map) {
    $file=Join-Path $env:TEMP $pair[0]
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
      throw 'PINNED_SOURCE_MISSING'
    }
    if ((GitBlob $file) -ne $pair[1]) { throw 'PINNED_SOURCE_BLOB_MISMATCH' }
    VerifySource $file
  }

  $stage='VERIFY_UNCHANGED_TASK'
  $scheduler=New-Object -ComObject 'Schedule.Service'
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $systemTask=$folder.GetTask('MspOnecHttpsAgentSystem')
  $personalTask=$folder.GetTask('MspOnecHttpsAgentProbe')
  $def=$systemTask.Definition
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList @($def.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
  $exe=Join-Path $PSHOME 'powershell.exe'
  $arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
     $oldAgent+'" -CurlExe "'+$curl+'" -CaBundle "'+$ca+'"')
  if (-not $systemTask.Enabled -or $def.Triggers.Count -ne 1 -or
      -not $def.Triggers.Item(1).Enabled -or $def.Actions.Count -ne 1 -or
      $personalTask.Enabled -or $sid -ne 'S-1-5-19' -or
      $def.Principal.LogonType -ne 5 -or $def.Principal.RunLevel -ne 0 -or
      $def.Actions.Item(1).Path -ne $exe -or
      $def.Actions.Item(1).Arguments -cne $arguments) {
    throw 'OPERATING_TASK_MISMATCH'
  }
  $stage='BACKUP_NONACTIVE_HELPERS'
  New-Item -ItemType Directory -Path $backupDir -ErrorAction Stop | Out-Null
  Copy-Item -LiteralPath $helper -Destination (Join-Path $backupDir 'old-helper.ps1') -ErrorAction Stop
  Copy-Item -LiteralPath $smoke -Destination (Join-Path $backupDir 'old-smoke.ps1') -ErrorAction Stop
  if ((GitBlob (Join-Path $backupDir 'old-helper.ps1')) -ne $previousHelper -or
      (GitBlob (Join-Path $backupDir 'old-smoke.ps1')) -ne $previousSmoke) {
    throw 'OLD_HELPER_BACKUP_INVALID'
  }
  $changedHelpers=$true
  $stage='INSTALL_FIXED_READONLY_HELPERS'
  Copy-Item -LiteralPath (Join-Path $env:TEMP 'onec-natural-final-odata.ps1') -Destination $helper -Force -ErrorAction Stop
  Copy-Item -LiteralPath (Join-Path $env:TEMP 'onec-natural-final-smoke.ps1') -Destination $smoke -Force -ErrorAction Stop
  Copy-Item -LiteralPath (Join-Path $env:TEMP 'onec-natural-final-json.ps1') -Destination $json -ErrorAction Stop
  Copy-Item -LiteralPath (Join-Path $env:TEMP 'onec-natural-final-writer.ps1') -Destination $writer -ErrorAction Stop
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  foreach($file in @($helper,$smoke,$json,$writer)) {
    & $ic $file '/reset' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'HELPER_ACL_FAILED' }
  }
  foreach($pair in @(@($helper,$expectedHelper),@($smoke,$expectedSmoke),
                     @($json,$expectedJson),@($writer,$expectedWriter))) {
    if ((GitBlob $pair[0]) -ne $pair[1]) { throw 'INSTALLED_HELPER_HASH_MISMATCH' }
  }

  $stage='BACKUP_AND_ATOMIC_SWAP_AGENT'
  $working=Join-Path $bin 'onec-system-probe-poll.ps1.natural-v4-candidate'
  if (Test-Path -LiteralPath $working) { throw 'CANDIDATE_ALREADY_EXISTS' }
  Copy-Item -LiteralPath (Join-Path $env:TEMP 'onec-natural-final-poller.ps1') -Destination $working -ErrorAction Stop
  & $ic $working '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (GitBlob $working) -ne $expectedAgent) {
    throw 'CANDIDATE_PIN_FAILED'
  }
  $backup=Join-Path $bin ('onec-system-probe-poll.ps1.backup-final-v4-'+
      [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'.ps1')
  if (Test-Path -LiteralPath $backup) { throw 'BACKUP_ALREADY_EXISTS' }
  $swapUtc=[DateTime]::UtcNow
  $swapLocal=Get-Date
  [IO.File]::Replace($working,$oldAgent,$backup)
  $changedAgent=$true
  if ((GitBlob $oldAgent) -ne $expectedAgent -or
      (GitBlob $backup) -ne $previousAgent) { throw 'ATOMIC_SWAP_HASH_MISMATCH' }

  $stage='AUTOMATIC_TIMER_HEARTBEAT'
  $accepted=$false
  for($i=0;$i -lt 90;$i++) {
    Start-Sleep -Seconds 2
    $checkTask=$folder.GetTask('MspOnecHttpsAgentSystem')
    if (-not $checkTask.Enabled -or
        -not $checkTask.Definition.Triggers.Item(1).Enabled) {
      throw 'SYSTEM_TRIGGER_CHANGED'
    }
    if (Test-Path -LiteralPath $health -PathType Leaf) {
      $fileInfo=Get-Item -LiteralPath $health
      if ($fileInfo.LastWriteTimeUtc -ge $swapUtc -and
          $checkTask.LastRunTime -ge $swapLocal.AddSeconds(-2)) {
        $line=[IO.File]::ReadAllText($health,[Text.Encoding]::ASCII).Trim()
        if ($line -match '^UTC=[0-9TZ:-]+;STATUS=(POLL_OK|PROBE_ACK);VERSION=ODATA_NATURAL_V1$') {
          $accepted=$true;break
        }
        if ($line -match '^UTC=[0-9TZ:-]+;STATUS=FAIL;VERSION=ODATA_NATURAL_V1$') {
          throw 'NEW_AGENT_HEARTBEAT_FAILED'
        }
      }
    }
  }
  if (-not $accepted) { throw 'AUTOMATIC_TIMER_HEARTBEAT_TIMEOUT' }
  Write-Output 'ONEC_NATURAL_CUTOVER_V4'
  Write-Output 'V4_PHYSICAL_READONLY_TWO_CARD_SMOKE=PASS'
  Write-Output 'OLD_AGENT_BACKUP=PASS'
  Write-Output 'AUTOMATIC_SYSTEM_HEARTBEAT=PASS'
  Write-Output 'SYSTEM_TIMER_CHANGED=NO'
  Write-Output 'OLD_GUID_TOOL_PRESERVED=YES'
  Write-Output 'NATURAL_VPS_E2E=NOT_TESTED'
  Write-Output 'RESULT=PASS'
} catch {
  $reason=$_.Exception.Message
  $allowed=@('WRONG_HOST_OR_POWERSHELL','ADMIN_REQUIRED','AGENT_DIRECTORY_MISSING',
   'REQUIRED_FILE_MISSING','OLD_AGENT_STATE_CHANGED','JSON_ALREADY_INSTALLED',
   'WRITER_ALREADY_INSTALLED','CUTOVER_STAGE_ALREADY_EXISTS',
   'REAL_LOCAL_SERVICE_V4_SMOKE_NOT_ACCEPTED','PINNED_SOURCE_MISSING',
   'PINNED_SOURCE_BLOB_MISMATCH','PS2_UTF8_BOM_REQUIRED','PS2_GUARD_MISSING',
   'PS2_PARSE_FAILED','OPERATING_TASK_MISMATCH','OLD_HELPER_BACKUP_INVALID',
   'HELPER_ACL_FAILED','INSTALLED_HELPER_HASH_MISMATCH','CANDIDATE_ALREADY_EXISTS',
   'CANDIDATE_PIN_FAILED','BACKUP_ALREADY_EXISTS','ATOMIC_SWAP_HASH_MISMATCH',
   'SYSTEM_TRIGGER_CHANGED','NEW_AGENT_HEARTBEAT_FAILED',
   'AUTOMATIC_TIMER_HEARTBEAT_TIMEOUT')
  if ($allowed -notcontains $reason) { $reason='UNCLASSIFIED_FAILURE' }
  Write-Output ('RESULT=FAIL;STAGE='+$stage+';GATE='+$reason)
  if ($changedAgent -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
    try {
      $rollback=Join-Path $bin ('onec-system-probe-poll.ps1.rollback-'+[Guid]::NewGuid().ToString('N'))
      Copy-Item -LiteralPath $backup -Destination $rollback -ErrorAction Stop
      [IO.File]::Replace($rollback,$oldAgent,$null)
      if ((GitBlob $oldAgent) -eq $previousAgent) {
        Write-Output 'OLD_AGENT_ROLLBACK=PASS'
      } else { Write-Output 'OLD_AGENT_ROLLBACK=NOT_CONFIRMED' }
    } catch { Write-Output 'OLD_AGENT_ROLLBACK=FAILED' }
  } else { Write-Output 'OPERATING_AGENT_UNCHANGED=YES' }
  if ($changedHelpers -and (Test-Path -LiteralPath (Join-Path $backupDir 'old-helper.ps1'))) {
    try {
      Copy-Item -LiteralPath (Join-Path $backupDir 'old-helper.ps1') -Destination $helper -Force -ErrorAction Stop
      Copy-Item -LiteralPath (Join-Path $backupDir 'old-smoke.ps1') -Destination $smoke -Force -ErrorAction Stop
      if (Test-Path -LiteralPath $json) {Remove-Item -LiteralPath $json -Force}
      if (Test-Path -LiteralPath $writer) {Remove-Item -LiteralPath $writer -Force}
      if ((GitBlob $helper) -eq $previousHelper -and
          (GitBlob $smoke) -eq $previousSmoke) {
        Write-Output 'OLD_HELPERS_ROLLBACK=PASS'
      } else { Write-Output 'OLD_HELPERS_ROLLBACK=NOT_CONFIRMED' }
    } catch { Write-Output 'OLD_HELPERS_ROLLBACK=FAILED' }
  }
  exit 1
} finally {
  if ($working -and (Test-Path -LiteralPath $working -PathType Leaf)) {
    Remove-Item -LiteralPath $working -Force -ErrorAction SilentlyContinue
  }
}

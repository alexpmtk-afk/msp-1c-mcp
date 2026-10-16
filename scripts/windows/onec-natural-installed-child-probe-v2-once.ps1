#requires -version 2
# Admin-launched one-time diagnostic. No active-agent or task-schedule changes.
param([Parameter(Mandatory=$true)][string]$PinnedProbe)
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$active=Join-Path $bin 'onec-system-probe-poll.ps1'
$main=Join-Path $bin 'onec-system-odata-natural.ps1'
$probe=Join-Path $bin 'onec-natural-installed-child-probe-v2.ps1'
$receipt=Join-Path $state 'natural-stock-installed-child-shape-v2.txt'
$taskName='MspOnecInstalledNaturalShapeV2Once'
$expected='23c62c67d55b2ab56da31b6335ba51771486e7f2'
$stage='PREFLIGHT'
$folder=$null
$created=$false
$installed=$false
function Blob([string]$file) {
  [byte[]]$raw=[IO.File]::ReadAllBytes($file)
  $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$raw.Length+[char]0))
  $mem=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $mem.Write($header,0,$header.Length);$mem.Write($raw,0,$raw.Length)
    $mem.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($mem))).Replace('-','').ToLowerInvariant()
  } finally { $mem.Close();$sha.Clear() }
}
try {
  if ($env:COMPUTERNAME -cne 'SRV' -or $PSVersionTable.PSVersion.Major -ne 2) {
    throw 'WRONG_HOST'
  }
  $who=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
  if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  if ($PinnedProbe -cne (Join-Path $env:TEMP 'onec-natural-shape-v2-probe-verified.ps1')) {
    throw 'BAD_PREFETCH_PATH'
  }
  if ((Test-Path -LiteralPath $probe -PathType Leaf) -or
      (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    throw 'DIAGNOSTIC_ALREADY_PRESENT'
  }
  if (-not (Test-Path -LiteralPath $PinnedProbe -PathType Leaf) -or
      -not (Test-Path -LiteralPath $main -PathType Leaf) -or
      -not (Test-Path -LiteralPath $active -PathType Leaf)) {
    throw 'MISSING_REQUIRED_FILE'
  }
  if ((Blob $PinnedProbe) -ne $expected -or
      (Blob $active) -ne '006a0b618575b4ab3a00b54c2863a436841e00ed' -or
      (Blob $main) -ne '08c23d0d6316ba7ddf1fd3e0f62e3269314838c7') {
    throw 'SOURCE_SHA_MISMATCH'
  }
  $bytes=[IO.File]::ReadAllBytes($PinnedProbe)
  if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or
      $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw 'SOURCE_BOM_INVALID' }
  $tokensErrors=$null
  $code=[IO.File]::ReadAllText($PinnedProbe,[Text.Encoding]::UTF8)
  $null=[Management.Automation.PSParser]::Tokenize($code,[ref]$tokensErrors)
  if ($tokensErrors -and $tokensErrors.Count) { throw 'SOURCE_PARSE_FAILED' }

  $stage='VERIFY_SYSTEM_IDENTITY'
  $sched=New-Object -ComObject 'Schedule.Service'
  $sched.Connect()
  $folder=$sched.GetFolder('\')
  $system=$folder.GetTask('MspOnecHttpsAgentSystem')
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList @($system.Definition.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
  if (-not $system.Enabled -or $sid -ne 'S-1-5-19' -or
      $system.Definition.Principal.LogonType -ne 5 -or
      -not $system.Definition.Triggers.Item(1).Enabled) { throw 'SYSTEM_TASK_CHANGED' }
  foreach($task in $folder.GetTasks(0)) {
    if ($task.Name -eq $taskName) { throw 'DIAGNOSTIC_TASK_EXISTS' }
  }

  $previous=Join-Path $state 'natural-stock-installed-child-result.txt'
  if (-not (Test-Path -LiteralPath $previous -PathType Leaf)) {
    throw 'PREVIOUS_PROBE_RECEIPT_MISSING'
  }
  $oldText=[IO.File]::ReadAllText($previous,[Text.Encoding]::ASCII)
  if ($oldText -notmatch 'STDOUT_COUNT=MULTIPLE' -or
      $oldText -notmatch 'CHILD_EXIT_ZERO=YES') {
    throw 'PREVIOUS_PROBE_NOT_CONFIRMED'
  }
  $stage='STAGE_READONLY_PROBE'
  Copy-Item -LiteralPath $PinnedProbe -Destination $probe -ErrorAction Stop
  $installed=$true
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $probe '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (Blob $probe) -ne $expected) { throw 'PROBE_STAGING_FAIL' }
  $local=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $job=$sched.NewTask(0)
  $job.RegistrationInfo.Description='Isolated read-only inspect of installed natural helper subprocess output'
  $job.Principal.UserId=$local
  $job.Principal.LogonType=5
  $job.Principal.RunLevel=0
  $job.Settings.Enabled=$true
  $job.Settings.AllowDemandStart=$true
  $job.Settings.StartWhenAvailable=$false
  $job.Settings.ExecutionTimeLimit='PT4M'
  $act=$job.Actions.Create(0)
  $act.Path=Join-Path $PSHOME 'powershell.exe'
  $act.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$probe+'"')
  $registered=$folder.RegisterTaskDefinition($taskName,$job,2,$local,$null,5,$null)
  if ($null -eq $registered) { throw 'TASK_REGISTRATION_FAILED' }
  $created=$true
  if ($folder.GetTask($taskName).Definition.Triggers.Count -ne 0) {
    throw 'UNEXPECTED_AUTO_TRIGGER'
  }
  $stage='LOCAL_SERVICE_PROBE'
  $started=[DateTime]::UtcNow
  $null=$registered.Run($null)
  $ready=$false
  for($i=0;$i -lt 110;$i++) {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $receipt -PathType Leaf) {
      $info=Get-Item -LiteralPath $receipt
      if ($info.Length -le 400 -and $info.LastWriteTimeUtc -ge $started) {
        $ready=$true;break
      }
    }
  }
  if (-not $ready) { throw 'NO_FRESH_RECEIPT' }
  $lines=@([IO.File]::ReadAllLines($receipt,[Text.Encoding]::ASCII))
  # Fixed-shape, bounded, ASCII-only indicators; never return original stdout.
  if ($lines.Count -ne 11) { throw 'INVALID_REPORT_LINE_COUNT' }
  $prefixes=@('STAGE','CHILD_EXIT_ZERO','STDOUT_ITEM_COUNT','NAT_ITEM_COUNT',
    'NAT_STATUS','NAT_CARD_COUNT','OTHER_SHORT','OTHER_MEDIUM','OTHER_LONG',
    'OTHER_NONSTRING','OTHER_EMPTY')
  for($i=0;$i -lt $lines.Count;$i++) {
    if ($lines[$i] -notmatch ('^'+$prefixes[$i]+'=[A-Z0-9_]{1,40}
} catch {
  $reason=$_.Exception.Message
  if ($reason -notmatch '^[A-Z_]{1,60}$') { $reason='DIAGNOSTIC_FAILURE' }
  Write-Output ('DIAGNOSTIC=FAIL;STAGE='+$stage+';CODE='+$reason)
  Write-Output 'OPERATING_AGENT_CHANGED=NO'
} finally {
  if ($created -and $null -ne $folder) {
    try {
      $task=$folder.GetTask($taskName)
      if ($task.State -eq 4) { $task.Stop(0) }
      $folder.DeleteTask($taskName,0)
      Write-Output 'TEMPORARY_TASK_CLEANUP=PASS'
    } catch { Write-Output 'TEMPORARY_TASK_CLEANUP=RECHECK' }
  }
  if ($installed -and (Test-Path -LiteralPath $probe -PathType Leaf)) {
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  }
}
)) {
      throw 'INVALID_SANITIZED_LINE'
    }
  }
  foreach($line in $lines) { Write-Output $line }
  Write-Output 'OPERATING_AGENT_CHANGED=NO'
  if ($lines.Count -ne 6 -or
      $lines[0] -notmatch '^STAGE=[A-Z_]{1,60}$' -or
      $lines[1] -notmatch '^CHILD_EXIT_ZERO=(YES|NO|NOT_RUN)$' -or
      $lines[2] -notmatch '^STDOUT_COUNT=(ONE|ZERO|MULTIPLE|NOT_RUN)$' -or
      $lines[3] -notmatch '^NAT_WIRE_SHAPE=(YES|NO|NOT_RUN)$' -or
      $lines[4] -notmatch '^DECODED_STATUS=(PASS|UNAVAILABLE|OTHER|NOT_RUN)$' -or
      $lines[5] -notmatch '^DECODED_CARD_COUNT=(TWO|OTHER|NOT_RUN)$') {
      throw 'INVALID_SANITIZED_RESULT'
  }
  foreach($line in $lines) { Write-Output $line }
  Write-Output 'OPERATING_AGENT_CHANGED=NO'
} catch {
  $reason=$_.Exception.Message
  if ($reason -notmatch '^[A-Z_]{1,60}$') { $reason='DIAGNOSTIC_FAILURE' }
  Write-Output ('DIAGNOSTIC=FAIL;STAGE='+$stage+';CODE='+$reason)
  Write-Output 'OPERATING_AGENT_CHANGED=NO'
} finally {
  if ($created -and $null -ne $folder) {
    try {
      $task=$folder.GetTask($taskName)
      if ($task.State -eq 4) { $task.Stop(0) }
      $folder.DeleteTask($taskName,0)
      Write-Output 'TEMPORARY_TASK_CLEANUP=PASS'
    } catch { Write-Output 'TEMPORARY_TASK_CLEANUP=RECHECK' }
  }
  if ($installed -and (Test-Path -LiteralPath $probe -PathType Leaf)) {
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
  }
}

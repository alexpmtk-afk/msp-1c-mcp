#requires -version 2
# Administrator-approved exact retry after previously failed LocalService JSON dependency.
# Stage only 3 pinned GET-only files, prove real two-card read under LocalService,
# then atomically replace the existing poller, with rollback on heartbeat failure.
# Never changes IIS, 1C, credentials, task schedule, identities, or personal rights.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$taskName='MspOnecNaturalAcceptanceOnce'
$createdTask=$false
$readOnlySmokeReady=$false
$oldAgentReplaced=$false
$accepted=$false
$folder=$null
$backup=''
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$stage=Join-Path $env:TEMP 'OnecNaturalAgentCutover_V2_20261015'
$previousStage=Join-Path $env:TEMP 'OnecNaturalAgentCutover_20261015'
$jsonLib=Join-Path $bin 'onec-legacy-json.ps1'
$helpersUpdated=$false
$oldHelperBackup=$null
$oldSmokeBackup=$null
$oldReportBackup=$null
$previousHelperHash='31e15a0dcd6a6c23a879a9d121f400344d4b9fac'
$previousSmokeHash='5aa96846681bd51441d2cbc5c25a3d5250506ad9'
$poller=Join-Path $bin 'onec-system-probe-poll.ps1'
$candidate=Join-Path $bin 'onec-system-probe-poll.ps1.natural-candidate'
$helper=Join-Path $bin 'onec-system-odata-natural.ps1'
$smoke=Join-Path $bin 'onec-natural-live-smoke-runner.ps1'
$report=Join-Path $state 'natural-stock-live-smoke.txt'
$health=Join-Path $state 'last-status.txt'
$curl=Join-Path $bin 'curl.exe'
$ca=Join-Path $bin 'curl-ca-bundle.crt'
$sourceCommit='6a50c09f2a31d0b15891314ae94a3264ce240433'
$previousAgentBlob='c7ad87b2d6ec41b0124a083d1bdf3305f5aee71f'
$expected=@{
 'onec-system-probe-poll.ps1'='006a0b618575b4ab3a00b54c2863a436841e00ed';
 'onec-system-odata-natural.ps1'='9dcaf6039d6728adb123660df464f356f5e8b3d4';
 'onec-natural-live-smoke-runner.ps1'='0282d46c2935777a72987c37c1e4533a243a5842';
 'onec-legacy-json.ps1'='05a3939ed2b8eb28378b395fc8a1b52989b5c3d5'
}
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
  } finally { $sha.Clear();$stream.Close() }
}
function ParsePS2([string]$path) {
  $code=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
  $errors=$null
  $null=[Management.Automation.PSParser]::Tokenize($code,[ref]$errors)
  if ($errors -and $errors.Count -gt 0) { throw 'SOURCE_PARSE_FAILED' }
  if (-not $code.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) {
    throw 'SOURCE_GUARD_MISSING'
  }
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_POWERSHELL' }
  if ([Environment]::OSVersion.Version.Major -ne 6 -or
      [Environment]::OSVersion.Version.Minor -ne 1) { throw 'WRONG_WINDOWS' }
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
  if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  foreach($directory in @($bin,$state)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
      throw 'REQUIRED_DIRECTORY_MISSING'
    }
  }
  foreach($file in @($curl,$ca,$poller,
      (Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'),
      (Join-Path (Join-Path $root 'secrets') 'agent-token.machine.dpapi'))) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
      throw 'REQUIRED_FILE_MISSING'
    }
  }
  if ((GitBlob $poller) -ne $previousAgentBlob) { throw 'LIVE_SOURCE_CHANGED' }
  foreach($path in @($stage,$candidate,$jsonLib)) {
    if (Test-Path -LiteralPath $path) { throw 'V2_CANDIDATE_ALREADY_EXISTS' }
  }
  if (-not (Test-Path -LiteralPath $previousStage -PathType Container) -or
      -not (Test-Path -LiteralPath $helper -PathType Leaf) -or
      -not (Test-Path -LiteralPath $smoke -PathType Leaf) -or
      -not (Test-Path -LiteralPath $report -PathType Leaf)) {
    throw 'PREVIOUS_FAILED_STAGE_NOT_FOUND'
  }
  if ((GitBlob $helper) -ne $previousHelperHash -or
      (GitBlob $smoke) -ne $previousSmokeHash) {
    throw 'PREVIOUS_HELPERS_CHANGED'
  }
  $priorReceipt=[IO.File]::ReadAllText($report,[Text.Encoding]::UTF8).Trim()
  $wantedReceipt=('ONEC_NATURAL_STOCK_LIVE_SMOKE'+[Environment]::NewLine+'RESULT=FAIL')
  if ($priorReceipt -cne $wantedReceipt) { throw 'PREVIOUS_FAILURE_RECEIPT_CHANGED' }
  foreach($filename in @('onec-system-probe-poll.ps1','onec-system-odata-natural.ps1',
      'onec-natural-live-smoke-runner.ps1')) {
    $prior=Join-Path $previousStage $filename
    $expectedOld=if($filename -eq 'onec-system-odata-natural.ps1'){$previousHelperHash}
      elseif($filename -eq 'onec-natural-live-smoke-runner.ps1'){$previousSmokeHash}
      else{$expected['onec-system-probe-poll.ps1']}
    if (-not (Test-Path -LiteralPath $prior -PathType Leaf) -or
        (GitBlob $prior) -ne $expectedOld) {
      throw 'PREVIOUS_STAGE_NOT_VERIFIABLE'
    }
  }
  $phase='VERIFY_OPERATING_SCHEDULE'
  $scheduler=New-Object -ComObject 'Schedule.Service'
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $task=$folder.GetTask('MspOnecHttpsAgentSystem')
  $personal=$folder.GetTask('MspOnecHttpsAgentProbe')
  $definition=$task.Definition
  $principal=(New-Object Security.Principal.NTAccount -ArgumentList @($definition.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
  $exe=Join-Path $PSHOME 'powershell.exe'
  $args=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$poller+
    '" -CurlExe "'+$curl+'" -CaBundle "'+$ca+'"')
  if (-not $task.Enabled -or $definition.Triggers.Count -ne 1 -or
      -not $definition.Triggers.Item(1).Enabled -or
      $definition.Actions.Count -ne 1 -or $personal.Enabled -or
      $principal -ne 'S-1-5-19' -or
      $definition.Principal.LogonType -ne 5 -or
      $definition.Principal.RunLevel -ne 0 -or
      $definition.Actions.Item(1).Path -ne $exe -or
      $definition.Actions.Item(1).Arguments -ne $args) {
    throw 'OPERATING_TASK_NOT_EXPECTED'
  }
  foreach($other in $folder.GetTasks(0)) {
    if ($other.Name -eq $taskName) { throw 'SMOKE_TASK_ALREADY_EXISTS' }
  }
  $sid=New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19'
  $localService=$sid.Translate([Security.Principal.NTAccount]).Value

  $phase='DOWNLOAD_PINNED_SOURCE'
  New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/'+$sourceCommit+'/scripts/windows/'
  foreach($file in @('onec-system-probe-poll.ps1','onec-system-odata-natural.ps1',
      'onec-natural-live-smoke-runner.ps1','onec-legacy-json.ps1')) {
    $target=Join-Path $stage $file
    $arguments=@('-q','--fail','--silent','--show-error','--noproxy','*',
      '--tlsv1.2','--tls-max','1.2','--proto','=https','--max-redirs','0',
      '--cacert',$ca,'--connect-timeout','15','--max-time','45',
      '--output',$target,($url+$file))
    & $curl @arguments | Out-Null
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $target -PathType Leaf)) {
      throw 'PINNED_SOURCE_DOWNLOAD_FAILED'
    }
    if ((GitBlob $target) -ne $expected[$file]) {
      throw 'PINNED_SOURCE_HASH_MISMATCH'
    }
    ParsePS2 $target
  }
  $phase='INSTALL_SEPARATE_READ_ONLY_HELPER'
  $oldHelperBackup=Join-Path $stage 'previous-original-helper.ps1'
  $oldSmokeBackup=Join-Path $stage 'previous-original-smoke.ps1'
  $oldReportBackup=Join-Path $stage 'previous-original-smoke-result.txt'
  Copy-Item -LiteralPath $helper -Destination $oldHelperBackup -ErrorAction Stop
  Copy-Item -LiteralPath $smoke -Destination $oldSmokeBackup -ErrorAction Stop
  Copy-Item -LiteralPath $report -Destination $oldReportBackup -ErrorAction Stop
  $helpersUpdated=$true
  Copy-Item -LiteralPath (Join-Path $stage 'onec-system-odata-natural.ps1') -Destination $helper -Force -ErrorAction Stop
  Copy-Item -LiteralPath (Join-Path $stage 'onec-natural-live-smoke-runner.ps1') -Destination $smoke -Force -ErrorAction Stop
  Copy-Item -LiteralPath (Join-Path $stage 'onec-legacy-json.ps1') -Destination $jsonLib -ErrorAction Stop
  Remove-Item -LiteralPath $report -Force -ErrorAction Stop
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $helper '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'HELPER_ACL_FAILED' }
  & $ic $smoke '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'SMOKE_ACL_FAILED' }
  & $ic $jsonLib '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'JSON_ACL_FAILED' }
  if ((GitBlob $helper) -ne $expected['onec-system-odata-natural.ps1'] -or
      (GitBlob $smoke) -ne $expected['onec-natural-live-smoke-runner.ps1'] -or
      (GitBlob $jsonLib) -ne $expected['onec-legacy-json.ps1']) {
    throw 'INSTALLED_HELPER_MISMATCH'
  }

  $phase='MANUAL_LOCAL_SERVICE_SMOKE'
  $manual=$scheduler.NewTask(0)
  $manual.RegistrationInfo.Description='One time read-only NewBase natural search acceptance, no automatic triggers.'
  $manual.Principal.UserId=$localService
  $manual.Principal.LogonType=5
  $manual.Principal.RunLevel=0
  $manual.Settings.Enabled=$true
  $manual.Settings.AllowDemandStart=$true
  $manual.Settings.StartWhenAvailable=$false
  $manual.Settings.MultipleInstances=2
  $manual.Settings.ExecutionTimeLimit='PT4M'
  $action=$manual.Actions.Create(0)
  $action.Path=$exe
  $action.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$smoke+'"')
  $registered=$folder.RegisterTaskDefinition($taskName,$manual,2,$localService,$null,5,$null)
  if ($null -eq $registered) { throw 'SMOKE_TASK_REGISTRATION_FAILED' }
  $createdTask=$true
  $check=$folder.GetTask($taskName)
  if ($check.Definition.Triggers.Count -ne 0 -or
      $check.Definition.Principal.LogonType -ne 5 -or
      $check.Definition.Actions.Count -ne 1) {
    throw 'SMOKE_TASK_HAS_WRONG_GUARDS'
  }
  $started=[DateTime]::UtcNow
  $run=$check.Run($null)
  if ($null -eq $run) { throw 'SMOKE_START_REJECTED' }
  for($i=1;$i -le 115;$i++) {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $report -PathType Leaf) {
      $file=Get-Item -LiteralPath $report
      if ($file.LastWriteTimeUtc -ge $started) {
        $readOnlySmokeReady=$true
        break
      }
    }
  }
  if (-not $readOnlySmokeReady) { throw 'SMOKE_REPORT_TIMEOUT' }
  $receipt=[IO.File]::ReadAllText($report,[Text.Encoding]::UTF8).Trim()
  $expectedReceipt=@('ONEC_NATURAL_STOCK_LIVE_SMOKE',
    'PRODUCT_NAME_MATCHES=2','WAREHOUSE_NAME_EXACT=YES',
    'OBSERVED_STOCK_6=PASS','MISSING_BALANCE_QUALIFIED_ZERO=PASS',
    'RESULT=PASS') -join [Environment]::NewLine
  if ($receipt -cne $expectedReceipt) { throw 'LIVE_ODATA_SMOKE_FAILED' }
  Write-Output 'ONEC_NATURAL_SMOKE_TEST=PASS'
  Write-Output 'TWO_CARDS_6_AND_QUALIFIED_ZERO=PASS'

  $phase='ATOMIC_UPDATE_POLLING_SCRIPT'
  Copy-Item -LiteralPath (Join-Path $stage 'onec-system-probe-poll.ps1') -Destination $candidate -ErrorAction Stop
  & $ic $candidate '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (GitBlob $candidate) -ne $expected['onec-system-probe-poll.ps1']) {
    throw 'POLL_CANDIDATE_MISMATCH'
  }
  $backup=Join-Path $bin ('onec-system-probe-poll.ps1.backup-nat-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'.ps1')
  $agentUtc=[DateTime]::UtcNow
  $agentLocal=Get-Date
  [IO.File]::Replace($candidate,$poller,$backup)
  $oldAgentReplaced=$true
  if ((GitBlob $poller) -ne $expected['onec-system-probe-poll.ps1'] -or
      (GitBlob $backup) -ne $previousAgentBlob) {
    throw 'AGENT_REPLACEMENT_HASH_FAILED'
  }
  $phase='WAIT_SYSTEM_AUTOMATIC_HEARTBEAT'
  for($i=1;$i -le 85;$i++) {
    Start-Sleep -Seconds 2
    $current=$folder.GetTask('MspOnecHttpsAgentSystem')
    if (-not $current.Enabled -or
        -not $current.Definition.Triggers.Item(1).Enabled) {
      throw 'SYSTEM_TRIGGER_CHANGED'
    }
    if (Test-Path -LiteralPath $health -PathType Leaf) {
      $healthInfo=Get-Item -LiteralPath $health
      if ($healthInfo.LastWriteTimeUtc -ge $agentUtc -and
          $current.LastRunTime -ge $agentLocal.AddSeconds(-2)) {
        $status=[IO.File]::ReadAllText($health,[Text.Encoding]::ASCII).Trim()
        if ($status -match '^UTC=[0-9TZ:-]+;STATUS=(POLL_OK|PROBE_ACK);VERSION=ODATA_NATURAL_V1$') {
          $accepted=$true;break
        }
        if ($status -match '^UTC=[0-9TZ:-]+;STATUS=FAIL;VERSION=ODATA_NATURAL_V1$') {
          throw 'NEW_AGENT_HEARTBEAT_FAILED'
        }
      }
    }
  }
  if (-not $accepted) { throw 'NEW_AGENT_HEARTBEAT_TIMEOUT' }
  Write-Output 'ONEC_NATURAL_AGENT_CUTOVER_V2'
  Write-Output 'JSON_RUNTIME_CLR2_FALLBACK=INSTALLED'
  Write-Output 'SANDBOX_ODATA_LOCAL_SERVICE_SMOKE=PASS'
  Write-Output 'OLD_AGENT_BACKUP=YES'
  Write-Output 'SYSTEM_SCHEDULE_CHANGED=NO'
  Write-Output 'NEW_AGENT_AUTOMATIC_HEARTBEAT=PASS'
  Write-Output 'VPS_NATURAL_JOB_E2E=NOT_YET_TESTED'
  Write-Output 'RESULT=PASS'
} catch {
  $allowed=@('WRONG_MACHINE','WRONG_POWERSHELL','WRONG_WINDOWS','ADMIN_REQUIRED',
    'REQUIRED_DIRECTORY_MISSING','REQUIRED_FILE_MISSING','LIVE_SOURCE_CHANGED',
    'CANDIDATE_ALREADY_EXISTS','V2_CANDIDATE_ALREADY_EXISTS',
    'PREVIOUS_FAILED_STAGE_NOT_FOUND','PREVIOUS_HELPERS_CHANGED',
    'PREVIOUS_FAILURE_RECEIPT_CHANGED','PREVIOUS_STAGE_NOT_VERIFIABLE',
    'OPERATING_TASK_NOT_EXPECTED','SMOKE_TASK_ALREADY_EXISTS',
    'PINNED_SOURCE_DOWNLOAD_FAILED','PINNED_SOURCE_HASH_MISMATCH',
    'SOURCE_PARSE_FAILED','SOURCE_GUARD_MISSING','HELPER_ACL_FAILED',
    'JSON_ACL_FAILED',
    'SMOKE_ACL_FAILED','INSTALLED_HELPER_MISMATCH','SMOKE_TASK_REGISTRATION_FAILED',
    'SMOKE_TASK_HAS_WRONG_GUARDS','SMOKE_START_REJECTED','SMOKE_REPORT_TIMEOUT',
    'LIVE_ODATA_SMOKE_FAILED','POLL_CANDIDATE_MISMATCH',
    'AGENT_REPLACEMENT_HASH_FAILED','SYSTEM_TRIGGER_CHANGED',
    'NEW_AGENT_HEARTBEAT_FAILED','NEW_AGENT_HEARTBEAT_TIMEOUT')
  $reason=$_.Exception.Message
  if ($allowed -notcontains $reason) { $reason='UNKNOWN_INSTALL_ERROR' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  if ($oldAgentReplaced -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
    try {
      $restore=Join-Path $bin ('onec-system-probe-poll.ps1.restore-'+[Guid]::NewGuid().ToString('N'))
      Copy-Item -LiteralPath $backup -Destination $restore -ErrorAction Stop
      [IO.File]::Replace($restore,$poller,$null)
      if ((GitBlob $poller) -eq $previousAgentBlob) {
        Write-Output 'PREVIOUS_AGENT_ROLLBACK=PASS'
      } else {
        Write-Output 'PREVIOUS_AGENT_ROLLBACK=NOT_CONFIRMED'
      }
    } catch { Write-Output 'PREVIOUS_AGENT_ROLLBACK=FAILED' }
  } else {
    Write-Output 'OPERATING_AGENT_UNCHANGED=YES'
  }
  if ($helpersUpdated) {
    try {
      if ($null -ne $oldHelperBackup -and (Test-Path -LiteralPath $oldHelperBackup)) {
        Copy-Item -LiteralPath $oldHelperBackup -Destination $helper -Force
      }
      if ($null -ne $oldSmokeBackup -and (Test-Path -LiteralPath $oldSmokeBackup)) {
        Copy-Item -LiteralPath $oldSmokeBackup -Destination $smoke -Force
      }
      if ($null -ne $oldReportBackup -and (Test-Path -LiteralPath $oldReportBackup)) {
        Copy-Item -LiteralPath $oldReportBackup -Destination $report -Force
      }
      if (Test-Path -LiteralPath $jsonLib) {
        Remove-Item -LiteralPath $jsonLib -Force
      }
      if ((GitBlob $helper) -eq $previousHelperHash -and
          (GitBlob $smoke) -eq $previousSmokeHash) {
        Write-Output 'PREVIOUS_NONACTIVE_HELPERS_RESTORED=PASS'
      } else { Write-Output 'PREVIOUS_NONACTIVE_HELPERS_RESTORED=NOT_CONFIRMED' }
    } catch { Write-Output 'PREVIOUS_NONACTIVE_HELPERS_RESTORED=FAILED' }
  }
  exit 1
} finally {
  if ($createdTask -and $null -ne $folder) {
    try {
      $taskToStop=$folder.GetTask($taskName)
      if ($taskToStop.State -eq 4) { $taskToStop.Stop(0) }
      $folder.DeleteTask($taskName,0)
      Write-Output 'ONE_SHOT_TASK_CLEANUP=PASS'
    } catch { Write-Output 'ONE_SHOT_TASK_CLEANUP=NEEDS_INSPECTION' }
  }
  if (Test-Path -LiteralPath $candidate -PathType Leaf) {
    Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
  }
}

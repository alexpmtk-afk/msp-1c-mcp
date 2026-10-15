#requires -version 2
# ADMINISTRATOR-APPROVED ONE-SHOT ONLY. Registers a new manual-only
# LocalService task and invokes two pinned GET-only NewBase metadata scripts.
# Never modifies, disables or restarts MspOnecHttpsAgentSystem/Probe.
# Requires already staged and SHA-verified files from reviewed public commit.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PREFLIGHT'
$taskName='MspOnecNaturalSchemaOnce'
$staged=Join-Path $env:TEMP 'OnecNaturalSchema_20261015'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$helperFile='onec-natural-stock-schema-preflight.ps1'
$runnerFile='onec-natural-stock-schema-runner.ps1'
$helperSha='c82e433205ee3a8353165381c33a7a2f43892b50'
$runnerSha='079e7fe7760cd9a209c5973f91a3c5c75b87d6e3'
$helper=Join-Path $bin $helperFile
$runner=Join-Path $bin $runnerFile
$report=Join-Path $state 'natural-stock-schema-report.txt'
$createdTask=$false
$rootFolder=$null
$receiptReady=$false
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
  } finally { $sha.Clear(); $stream.Close() }
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_MACHINE' }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_POWERSHELL' }
  if ([Environment]::OSVersion.Version.Major -ne 6 -or
      [Environment]::OSVersion.Version.Minor -ne 1) { throw 'WRONG_WINDOWS' }
  $user=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $user
  if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  foreach($path in @($bin,$state,$staged)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
      throw 'REQUIRED_DIRECTORY_MISSING'
    }
  }
  $credential=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
  if (-not (Test-Path -LiteralPath $credential -PathType Leaf)) {
    throw 'READONLY_CREDENTIAL_NOT_ENROLLED'
  }
  if (Test-Path -LiteralPath $helper -PathType Leaf) { throw 'HELPER_ALREADY_INSTALLED' }
  if (Test-Path -LiteralPath $runner -PathType Leaf) { throw 'RUNNER_ALREADY_INSTALLED' }
  if (Test-Path -LiteralPath $report -PathType Leaf) { throw 'REPORT_ALREADY_PRESENT' }
  $srcHelper=Join-Path $staged $helperFile
  $srcRunner=Join-Path $staged $runnerFile
  if (-not (Test-Path -LiteralPath $srcHelper -PathType Leaf) -or
      -not (Test-Path -LiteralPath $srcRunner -PathType Leaf)) {
    throw 'STAGED_FILES_MISSING'
  }
  if ((GitBlob $srcHelper) -ne $helperSha -or (GitBlob $srcRunner) -ne $runnerSha) {
    throw 'STAGED_HASH_MISMATCH'
  }
  foreach($path in @($srcHelper,$srcRunner)) {
    $source=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    $errors=$null
    $null=[Management.Automation.PSParser]::Tokenize($source,[ref]$errors)
    if ($errors -and $errors.Count -gt 0) { throw 'PS2_PARSE_FAILED' }
    if (-not $source.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) {
      throw 'PS2_VERSION_GUARD_MISSING'
    }
  }
  $phase='EXISTING_TASK_GUARDS'
  $scheduler=New-Object -ComObject 'Schedule.Service'
  $scheduler.Connect()
  $rootFolder=$scheduler.GetFolder('\')
  $primary=$rootFolder.GetTask('MspOnecHttpsAgentSystem')
  $prior=$primary.Definition
  if (-not $primary.Enabled -or $prior.Principal.LogonType -ne 5 -or
      $prior.Triggers.Count -ne 1 -or -not $prior.Triggers.Item(1).Enabled) {
    throw 'SYSTEM_AGENT_NOT_HEALTHY'
  }
  foreach($existing in $rootFolder.GetTasks(0)) {
    if ($existing.Name -eq $taskName) { throw 'ONESHOT_TASK_ALREADY_EXISTS' }
  }
  $identity=New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19'
  $localService=$identity.Translate([Security.Principal.NTAccount]).Value

  $phase='STAGE_PINNED_FILES'
  Copy-Item -LiteralPath $srcHelper -Destination $helper -ErrorAction Stop
  Copy-Item -LiteralPath $srcRunner -Destination $runner -ErrorAction Stop
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $helper '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'HELPER_ACL_ERROR' }
  & $ic $runner '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'RUNNER_ACL_ERROR' }
  if ((GitBlob $helper) -ne $helperSha -or (GitBlob $runner) -ne $runnerSha) {
    throw 'INSTALLED_HASH_MISMATCH'
  }

  $phase='CREATE_SEPARATE_MANUAL_ONLY_TASK'
  $definition=$scheduler.NewTask(0)
  $definition.RegistrationInfo.Description='Read-only 1C NewBase article and warehouse metadata ONE-SHOT. No timer; separate from operational agent.'
  $definition.Principal.UserId=$localService
  $definition.Principal.LogonType=5
  $definition.Principal.RunLevel=0
  $definition.Settings.Enabled=$true
  $definition.Settings.AllowDemandStart=$true
  $definition.Settings.StartWhenAvailable=$false
  $definition.Settings.MultipleInstances=2
  $definition.Settings.ExecutionTimeLimit='PT4M'
  $definition.Settings.DisallowStartIfOnBatteries=$false
  $definition.Settings.StopIfGoingOnBatteries=$false
  # Deliberately no triggers: job cannot run periodically or from remote queue.
  $action=$definition.Actions.Create(0)
  $action.Path=(Join-Path $PSHOME 'powershell.exe')
  $action.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$runner+'"')
  $task=$rootFolder.RegisterTaskDefinition($taskName,$definition,2,$localService,$null,5,$null)
  if ($null -eq $task) { throw 'REGISTRATION_FAILED' }
  $createdTask=$true
  $check=$rootFolder.GetTask($taskName)
  if ($check.Definition.Triggers.Count -ne 0 -or
      $check.Definition.Principal.LogonType -ne 5 -or
      $check.Definition.Principal.RunLevel -ne 0 -or
      $check.Definition.Actions.Count -ne 1) {
    throw 'TASK_DEFINITION_INVALID'
  }
  $taskPrincipal=(New-Object Security.Principal.NTAccount -ArgumentList
    $check.Definition.Principal.UserId).Translate([Security.Principal.SecurityIdentifier]).Value
  if ($taskPrincipal -ne 'S-1-5-19') { throw 'TASK_NOT_LOCAL_SERVICE' }

  $phase='ONE_SHOT_METADATA_READ'
  $started=[DateTime]::UtcNow
  $run=$check.Run($null)
  if ($null -eq $run) { throw 'MANUAL_RUN_REJECTED' }
  for($i=1;$i -le 110;$i++) {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $report -PathType Leaf) {
      $info=Get-Item -LiteralPath $report
      if ($info.LastWriteTimeUtc -ge $started) {
        $receiptReady=$true
        break
      }
    }
  }
  if (-not $receiptReady) { throw 'ONE_SHOT_REPORT_TIMEOUT' }
  $raw=[IO.File]::ReadAllText($report,[Text.Encoding]::UTF8)
  if ($raw.Length -gt 15000 -or
      -not $raw.StartsWith('ONEC_NATURAL_STOCK_ONESHOT_RESULT') -or
      $raw -notmatch 'RESULT=PASS\s*$') {
    throw 'ONE_SHOT_REPORT_FAILED'
  }
  Write-Output 'ONEC_NATURAL_STOCK_SCHEMA_ONE_SHOT'
  Write-Output 'SYSTEM_TASK_CHANGED=NO'
  Write-Output 'NEW_TASK_HAS_TRIGGERS=NO'
  Write-Output 'LOCAL_SERVICE=YES'
  Write-Output 'ODATA_GET_ONLY=YES'
  Write-Output 'ONE_SHOT_REPORT=PASS'
  # Only the vetted, status-only wrapper report can be echoed.
  Write-Output $raw
  Write-Output 'RESULT=PASS'
} catch {
  $allowed=@('WRONG_MACHINE','WRONG_POWERSHELL','WRONG_WINDOWS','ADMIN_REQUIRED',
    'REQUIRED_DIRECTORY_MISSING','READONLY_CREDENTIAL_NOT_ENROLLED',
    'HELPER_ALREADY_INSTALLED','RUNNER_ALREADY_INSTALLED','REPORT_ALREADY_PRESENT',
    'STAGED_FILES_MISSING','STAGED_HASH_MISMATCH','PS2_PARSE_FAILED',
    'PS2_VERSION_GUARD_MISSING','SYSTEM_AGENT_NOT_HEALTHY',
    'ONESHOT_TASK_ALREADY_EXISTS','HELPER_ACL_ERROR','RUNNER_ACL_ERROR',
    'INSTALLED_HASH_MISMATCH','REGISTRATION_FAILED','TASK_DEFINITION_INVALID',
    'TASK_NOT_LOCAL_SERVICE','MANUAL_RUN_REJECTED','ONE_SHOT_REPORT_TIMEOUT',
    'ONE_SHOT_REPORT_FAILED')
  $reason=$_.Exception.Message
  if ($allowed -notcontains $reason) { $reason='ONE_SHOT_RUNTIME_ERROR' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  exit 1
} finally {
  # The one-shot task does not participate in the system agent. On timeout,
  # retain task/files for administrator inspection, never modify the live task.
  if ($createdTask -and $receiptReady -and $null -ne $rootFolder) {
    try {
      $rootFolder.DeleteTask($taskName,0)
      Write-Output 'ONESHOT_TASK_CLEANUP=PASS'
    } catch {
      Write-Output 'ONESHOT_TASK_CLEANUP=NEEDS_INSPECTION'
    }
  }
}

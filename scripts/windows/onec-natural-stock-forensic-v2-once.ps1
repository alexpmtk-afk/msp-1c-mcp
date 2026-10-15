#requires -version 2
# One authorized diagnostic retry using the original SHA-pinned GET-only helper
# already installed on SRV. New runner/report/task have V2 names to preserve
# all first-attempt evidence. No edits to active SRV agent or 1C database.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$taskName='MspOnecNaturalSchemaForensicV2'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$helper=Join-Path $bin 'onec-natural-stock-schema-preflight.ps1'
$installedRunner=Join-Path $bin 'onec-natural-stock-forensic-v2-runner.ps1'
$report=Join-Path $state 'natural-stock-schema-report-v2.txt'
$curl=Join-Path $bin 'curl.exe'
$ca=Join-Path $bin 'curl-ca-bundle.crt'
$staged=Join-Path $env:TEMP 'OnecNaturalSchemaForensic_20261015'
$runner=Join-Path $staged 'onec-natural-stock-forensic-v2-runner.ps1'
$existingHelperBlob='c82e433205ee3a8353165381c33a7a2f43892b50'
$runnerBlob='8299113a6cb5980af9f0b24ba5bf3bc82b5866e3'
$runnerCommit='9ee6e13c07f6f5790cdacc063ea4567c13c0a1cf'
$folder=$null
$createdTask=$false
$reportReady=$false
function GitBlob([string]$path) {
  [byte[]]$data=[IO.File]::ReadAllBytes($path)
  [byte[]]$head=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length+[char]0))
  $memory=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $memory.Write($head,0,$head.Length)
    $memory.Write($data,0,$data.Length)
    $memory.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($memory))).Replace('-','').ToLowerInvariant()
  } finally { $sha.Clear();$memory.Close() }
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
  foreach($p in @($helper,$curl,$ca)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw 'INSTALLED_FILE_MISSING' }
  }
  if (-not (Test-Path -LiteralPath $state -PathType Container)) {
    throw 'STATE_DIRECTORY_MISSING'
  }
  if ((GitBlob $helper) -ne $existingHelperBlob) { throw 'ORIGINAL_HELPER_HASH_MISMATCH' }
  if (-not (Test-Path -LiteralPath (Join-Path $state 'natural-stock-schema-report.txt') -PathType Leaf)) {
    throw 'FIRST_REPORT_MISSING'
  }
  if ((Test-Path -LiteralPath $installedRunner) -or
      (Test-Path -LiteralPath $report) -or
      (Test-Path -LiteralPath $staged)) {
    throw 'FORENSIC_V2_ALREADY_STARTED'
  }
  $phase='CHECK_OPERATIONAL_TASK'
  $scheduler=New-Object -ComObject 'Schedule.Service'
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $primary=$folder.GetTask('MspOnecHttpsAgentSystem')
  $definition=$primary.Definition
  if (-not $primary.Enabled -or $definition.Triggers.Count -ne 1 -or
      -not $definition.Triggers.Item(1).Enabled -or $definition.Principal.LogonType -ne 5) {
    throw 'OPERATIONAL_TASK_UNEXPECTED'
  }
  foreach($existing in $folder.GetTasks(0)) {
    if ($existing.Name -eq $taskName) { throw 'V2_TASK_ALREADY_EXISTS' }
  }
  $sid=New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19'
  $localService=$sid.Translate([Security.Principal.NTAccount]).Value
  $phase='DOWNLOAD_VERIFIED_FORENSIC_RUNNER'
  New-Item -ItemType Directory -Path $staged -ErrorAction Stop | Out-Null
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/'+$runnerCommit+
       '/scripts/windows/onec-natural-stock-forensic-v2-runner.ps1'
  $args=@('-q','--fail','--silent','--show-error','--noproxy','*',
    '--tlsv1.2','--tls-max','1.2','--proto','=https','--max-redirs','0',
    '--cacert',$ca,'--connect-timeout','15','--max-time','40',
    '--output',$runner,$url)
  & $curl @args | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw 'RUNNER_DOWNLOAD_FAILED'
  }
  if ((GitBlob $runner) -ne $runnerBlob) { throw 'RUNNER_HASH_MISMATCH' }
  $source=[IO.File]::ReadAllText($runner,[Text.Encoding]::UTF8)
  $errors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize($source,[ref]$errors)
  if ($errors -and $errors.Count -gt 0) { throw 'V2_PS2_PARSE_FAILED' }
  if (-not $source.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) {
    throw 'V2_PS2_GUARD_MISSING'
  }
  $phase='INSTALL_V2_ONLY'
  Copy-Item -LiteralPath $runner -Destination $installedRunner -ErrorAction Stop
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $installedRunner '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (GitBlob $installedRunner) -ne $runnerBlob) {
    throw 'RUNNER_INSTALL_FAILED'
  }
  $taskDefinition=$scheduler.NewTask(0)
  $taskDefinition.RegistrationInfo.Description='One-shot diagnostic only: preserves prior NewBase read failure phase. No existing task changes.'
  $taskDefinition.Principal.UserId=$localService
  $taskDefinition.Principal.LogonType=5
  $taskDefinition.Principal.RunLevel=0
  $taskDefinition.Settings.Enabled=$true
  $taskDefinition.Settings.AllowDemandStart=$true
  $taskDefinition.Settings.StartWhenAvailable=$false
  $taskDefinition.Settings.MultipleInstances=2
  $taskDefinition.Settings.ExecutionTimeLimit='PT4M'
  # Intentionally zero triggers; no repetition, autostart or gateway effects.
  $action=$taskDefinition.Actions.Create(0)
  $action.Path=(Join-Path $PSHOME 'powershell.exe')
  $action.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
    $installedRunner+'"')
  $task=$folder.RegisterTaskDefinition($taskName,$taskDefinition,2,$localService,$null,5,$null)
  if ($null -eq $task) { throw 'V2_TASK_REGISTRATION_FAILED' }
  $createdTask=$true
  $check=$folder.GetTask($taskName)
  if ($check.Definition.Triggers.Count -ne 0 -or
      $check.Definition.Principal.LogonType -ne 5 -or
      $check.Definition.Principal.RunLevel -ne 0 -or
      $check.Definition.Actions.Count -ne 1) {
    throw 'V2_TASK_SETTINGS_INVALID'
  }
  $account=New-Object Security.Principal.NTAccount -ArgumentList @($check.Definition.Principal.UserId)
  if ($account.Translate([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-19') {
    throw 'V2_TASK_IDENTITY_INVALID'
  }
  $phase='RUN_READONLY_FORENSIC'
  $started=[DateTime]::UtcNow
  $handle=$check.Run($null)
  if ($null -eq $handle) { throw 'V2_MANUAL_START_FAILED' }
  for($i=1;$i -le 115;$i++) {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $report -PathType Leaf) {
      $file=Get-Item -LiteralPath $report
      if ($file.LastWriteTimeUtc -ge $started) {
        $reportReady=$true
        break
      }
    }
  }
  if (-not $reportReady) { throw 'V2_REPORT_TIMEOUT' }
  $raw=[IO.File]::ReadAllText($report,[Text.Encoding]::UTF8)
  if ($raw.Length -gt 10000 -or
      -not $raw.StartsWith('ONEC_NATURAL_STOCK_FORENSIC_V2') -or
      $raw -notmatch 'PROBE_PHASE=(PRECHECK|SCHEMA_GET|EXACT_ARTICLE_FILTER|COMPLETE|NO_CLASSIFIED_STAGE|RUNNER_FAILURE)' -or
      $raw -notmatch 'PROBE_RESULT=(PASS|PROBE_FAILED|RUNNER_ERROR)') {
    throw 'V2_REPORT_INVALID'
  }
  Write-Output 'ONEC_NATURAL_STOCK_FORENSIC_RUN'
  Write-Output 'ORIGINAL_AGENT_CHANGED=NO'
  Write-Output 'ORIGINAL_HELPER_CHANGED=NO'
  Write-Output 'DIAGNOSTIC_CAPTURE=PASS'
  Write-Output $raw
  Write-Output 'RESULT=PASS;STAGE=DIAGNOSTIC_CAPTURE_ONLY'
} catch {
  $allowed=@('WRONG_MACHINE','WRONG_POWERSHELL','WRONG_WINDOWS','ADMIN_REQUIRED',
    'INSTALLED_FILE_MISSING','STATE_DIRECTORY_MISSING',
    'ORIGINAL_HELPER_HASH_MISMATCH','FIRST_REPORT_MISSING',
    'FORENSIC_V2_ALREADY_STARTED','OPERATIONAL_TASK_UNEXPECTED',
    'V2_TASK_ALREADY_EXISTS','RUNNER_DOWNLOAD_FAILED','RUNNER_HASH_MISMATCH',
    'V2_PS2_PARSE_FAILED','V2_PS2_GUARD_MISSING','RUNNER_INSTALL_FAILED',
    'V2_TASK_REGISTRATION_FAILED','V2_TASK_SETTINGS_INVALID',
    'V2_TASK_IDENTITY_INVALID','V2_MANUAL_START_FAILED','V2_REPORT_TIMEOUT',
    'V2_REPORT_INVALID')
  $reason=$_.Exception.Message
  if ($allowed -notcontains $reason) { $reason='FORENSIC_UNCLASSIFIED' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  exit 1
} finally {
  if ($createdTask -and $reportReady -and $null -ne $folder) {
    try {
      $folder.DeleteTask($taskName,0)
      Write-Output 'V2_TASK_CLEANUP=PASS'
    } catch {
      Write-Output 'V2_TASK_CLEANUP=NEEDS_INSPECTION'
    }
  }
}

#requires -version 2
# Authorized, manual-only LocalService one-shot of the CLR2-safe OData probe.
# Original SRV polling task, V1/V2 scripts, reports and 1C stay UNCHANGED.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$taskName='MspOnecNaturalSchemaV3'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$secret=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
$curl=Join-Path $bin 'curl.exe'
$ca=Join-Path $bin 'curl-ca-bundle.crt'
$helper=Join-Path $bin 'onec-natural-stock-schema-v3.ps1'
$report=Join-Path $state 'natural-stock-schema-report-v3.txt'
$staged=Join-Path $env:TEMP 'OnecNaturalSchemaV3_20261015'
$download=Join-Path $staged 'onec-natural-stock-schema-v3.ps1'
$fixedCommit='21a2943c1212a477cf7efc7a24026482f2814039'
$fixedBlob='f8f34426e1be4cb4d14a9003774e4876b1167698'
$oldHelperBlob='c82e433205ee3a8353165381c33a7a2f43892b50'
$folder=$null
$created=$false
$reportReady=$false
function GitBlob([string]$path) {
  [byte[]]$bytes=[IO.File]::ReadAllBytes($path)
  [byte[]]$heading=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0))
  $stream=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $stream.Write($heading,0,$heading.Length)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
  } finally { $sha.Clear(); $stream.Close() }
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
  foreach($file in @($curl,$ca,$secret,(Join-Path $bin 'onec-natural-stock-schema-preflight.ps1'))) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
      throw 'PINNED_PREREQUISITE_MISSING'
    }
  }
  $v1=Join-Path $bin 'onec-natural-stock-schema-preflight.ps1'
  if ((GitBlob $v1) -ne $oldHelperBlob) { throw 'ORIGINAL_HELPER_CHANGED' }
  if (-not (Test-Path -LiteralPath $state -PathType Container)) {
    throw 'STATE_DIRECTORY_MISSING'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $state 'natural-stock-schema-report-v2.txt') -PathType Leaf)) {
    throw 'V2_EVIDENCE_MISSING'
  }
  if ((Test-Path -LiteralPath $helper) -or
      (Test-Path -LiteralPath $report) -or
      (Test-Path -LiteralPath $staged)) {
    throw 'V3_ALREADY_STARTED'
  }
  $phase='EXISTING_AGENT_READONLY_CHECK'
  $scheduler=New-Object -ComObject 'Schedule.Service'
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $operational=$folder.GetTask('MspOnecHttpsAgentSystem')
  $definition=$operational.Definition
  if (-not $operational.Enabled -or $definition.Triggers.Count -ne 1 -or
      -not $definition.Triggers.Item(1).Enabled -or $definition.Principal.LogonType -ne 5) {
    throw 'OPERATIONAL_AGENT_UNEXPECTED'
  }
  foreach($task in $folder.GetTasks(0)) {
    if ($task.Name -eq $taskName) { throw 'V3_TASK_ALREADY_EXISTS' }
  }
  $sid=New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19'
  $localService=$sid.Translate([Security.Principal.NTAccount]).Value
  $phase='DOWNLOAD_PINNED_HELPER'
  New-Item -ItemType Directory -Path $staged -ErrorAction Stop | Out-Null
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/'+$fixedCommit+
       '/scripts/windows/onec-natural-stock-schema-v3.ps1'
  $args=@('-q','--fail','--silent','--show-error','--noproxy','*',
      '--tlsv1.2','--tls-max','1.2','--proto','=https','--max-redirs','0',
      '--cacert',$ca,'--connect-timeout','15','--max-time','40',
      '--output',$download,$url)
  & $curl @args | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $download -PathType Leaf)) {
    throw 'V3_DOWNLOAD_FAILED'
  }
  if ((GitBlob $download) -ne $fixedBlob) { throw 'V3_HELPER_HASH_MISMATCH' }
  $content=[IO.File]::ReadAllText($download,[Text.Encoding]::UTF8)
  $parseErrors=$null
  $null=[System.Management.Automation.PSParser]::Tokenize($content,[ref]$parseErrors)
  if ($parseErrors -and $parseErrors.Count -gt 0) { throw 'V3_PS2_PARSE_FAILED' }
  if (-not $content.TrimStart([char]0xFEFF).StartsWith('#requires -version 2') -or
      -not $content.Contains('ProhibitDtd=$true') -or
      $content.Contains('DtdProcessing]::')) {
    throw 'V3_CLR2_GUARD_MISSING'
  }
  $phase='INSTALL_SEPARATE_V3'
  Copy-Item -LiteralPath $download -Destination $helper -ErrorAction Stop
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $helper '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (GitBlob $helper) -ne $fixedBlob) {
    throw 'V3_COPY_OR_ACL_FAILURE'
  }
  $definition=$scheduler.NewTask(0)
  $definition.RegistrationInfo.Description='MSP 1C NewBase CLR2 schema diagnosis; one shot only, no changes to operational agent.'
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
  # No scheduler triggers. This is NOT a remote code execution endpoint.
  $action=$definition.Actions.Create(0)
  $action.Path=(Join-Path $PSHOME 'powershell.exe')
  $action.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
                     $helper+'" -ExpectedComputerName SRV')
  $task=$folder.RegisterTaskDefinition($taskName,$definition,2,$localService,$null,5,$null)
  if ($null -eq $task) { throw 'V3_TASK_REGISTRATION_FAILED' }
  $created=$true
  $check=$folder.GetTask($taskName)
  if ($check.Definition.Triggers.Count -ne 0 -or
      $check.Definition.Principal.LogonType -ne 5 -or
      $check.Definition.Principal.RunLevel -ne 0 -or
      $check.Definition.Actions.Count -ne 1) { throw 'V3_TASK_INVALID' }
  $account=New-Object Security.Principal.NTAccount -ArgumentList @($check.Definition.Principal.UserId)
  if ($account.Translate([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-19') {
    throw 'V3_NOT_LOCAL_SERVICE'
  }
  $phase='RUN_V3_READONLY'
  $started=[DateTime]::UtcNow
  $run=$check.Run($null)
  if ($null -eq $run) { throw 'V3_START_REJECTED' }
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
  if (-not $reportReady) { throw 'V3_REPORT_TIMEOUT' }
  $raw=[IO.File]::ReadAllText($report,[Text.Encoding]::UTF8)
  if ($raw.Length -gt 10000 -or
      -not $raw.StartsWith('ONEC_NATURAL_STOCK_SCHEMA_V3') -or
      $raw -notmatch '(?m)^RESULT=(PASS|FAIL)\s*$' -or
      $raw -match '[^A-Za-z0-9_=\r\n]') {
    throw 'V3_REPORT_NOT_SANITIZED'
  }
  Write-Output 'ONEC_NATURAL_STOCK_V3'
  Write-Output 'V3_REPORT_CAPTURED=YES'
  Write-Output 'ORIGINAL_AGENT_CHANGED=NO'
  Write-Output $raw
  Write-Output 'RESULT=PASS;STAGE=REPORT_CAPTURE_ONLY'
} catch {
  $allowed=@('WRONG_MACHINE','WRONG_POWERSHELL','WRONG_WINDOWS','ADMIN_REQUIRED',
    'PINNED_PREREQUISITE_MISSING','ORIGINAL_HELPER_CHANGED',
    'STATE_DIRECTORY_MISSING','V2_EVIDENCE_MISSING','V3_ALREADY_STARTED',
    'OPERATIONAL_AGENT_UNEXPECTED','V3_TASK_ALREADY_EXISTS',
    'V3_DOWNLOAD_FAILED','V3_HELPER_HASH_MISMATCH','V3_PS2_PARSE_FAILED',
    'V3_CLR2_GUARD_MISSING','V3_COPY_OR_ACL_FAILURE',
    'V3_TASK_REGISTRATION_FAILED','V3_TASK_INVALID','V3_NOT_LOCAL_SERVICE',
    'V3_START_REJECTED','V3_REPORT_TIMEOUT','V3_REPORT_NOT_SANITIZED')
  $reason=$_.Exception.Message
  if ($allowed -notcontains $reason) { $reason='V3_UNCLASSIFIED' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  exit 1
} finally {
  if ($created -and $reportReady -and $null -ne $folder) {
    try {
      $folder.DeleteTask($taskName,0)
      Write-Output 'V3_TASK_CLEANUP=PASS'
    } catch { Write-Output 'V3_TASK_CLEANUP=NEEDS_INSPECTION' }
  }
}

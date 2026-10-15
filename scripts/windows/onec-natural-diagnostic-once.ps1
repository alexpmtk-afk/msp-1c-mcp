#requires -version 2
# One-shot local administrative diagnostic. Physical SRV only. No replacement
# of any operating 1C agent, no service modifications, no 1C writes.
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$live=Join-Path $bin 'onec-system-probe-poll.ps1'
$debug=Join-Path $bin 'onec-natural-diagnostic-helper.ps1'
$report=Join-Path $state 'natural-stock-diagnostic-result.txt'
$curl=Join-Path $bin 'curl.exe'
$ca=Join-Path $bin 'curl-ca-bundle.crt'
$taskName='MspOnecNaturalDiagnosticOnce'
$expectedLive='c7ad87b2d6ec41b0124a083d1bdf3305f5aee71f'
$expectedDebug='25b692b7f4baf63667a6f25462846877371b8dc6'
$sourceCommit='e2b832baf30f4875eb9d7ed4911773d753c0c06b'
$staged=Join-Path $env:TEMP ('msp-onenatural-diagnostic-'+[Guid]::NewGuid().ToString('N')+'.ps1')
$folder=$null
$registered=$false
$installed=$false
$stage='PREFLIGHT'
function Blob([string]$file) {
  [byte[]]$data=[IO.File]::ReadAllBytes($file)
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
  if ($env:COMPUTERNAME -ne 'SRV' -or $PSVersionTable.PSVersion.Major -ne 2) {
    throw 'WRONG_ENVIRONMENT'
  }
  $who=[Security.Principal.WindowsIdentity]::GetCurrent()
  $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $who
  if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ADMIN_REQUIRED'
  }
  foreach($path in @($bin,$state)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
      throw 'NO_AGENT_FOLDER'
    }
  }
  foreach($path in @($live,$curl,$ca,(Join-Path $bin 'onec-system-odata-natural.ps1'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'NO_REQUIRED_FILE' }
  }
  if ((Blob $live) -ne $expectedLive) { throw 'OPERATING_AGENT_UNEXPECTED' }
  foreach($path in @($debug,$report)) {
    if (Test-Path -LiteralPath $path) { throw 'DIAGNOSTIC_PREEXISTS' }
  }
  $scheduler=New-Object -ComObject 'Schedule.Service'
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  foreach($task in $folder.GetTasks(0)) {
    if ($task.Name -eq $taskName) { throw 'DIAGNOSTIC_TASK_PREEXISTS' }
  }
  $stage='DOWNLOAD_PINNED_DEBUG_SOURCE'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/'+$sourceCommit+'/scripts/windows/onec-natural-diagnostic-helper.ps1'
  $curlArgs=@('-q','--fail','--silent','--show-error','--noproxy','*',
   '--tlsv1.2','--tls-max','1.2','--proto','=https','--max-redirs','0',
   '--cacert',$ca,'--connect-timeout','15','--max-time','45','--output',$staged,$url)
  & $curl @curlArgs | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $staged -PathType Leaf)) {
    throw 'PINNED_DOWNLOAD_FAILED'
  }
  if ((Blob $staged) -ne $expectedDebug) { throw 'SOURCE_HASH_MISMATCH' }
  $code=[IO.File]::ReadAllText($staged,[Text.Encoding]::UTF8)
  $parseErrors=$null
  $null=[Management.Automation.PSParser]::Tokenize($code,[ref]$parseErrors)
  if ($parseErrors -and $parseErrors.Count -gt 0) { throw 'PS2_PARSE_FAILED' }
  if (-not $code.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) {
    throw 'MISSING_PS2_GUARD'
  }
  $stage='STAGE_DEBUG_HELPER'
  Copy-Item -LiteralPath $staged -Destination $debug -ErrorAction Stop
  $installed=$true
  & (Join-Path $env:WINDIR 'System32\icacls.exe') $debug '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0 -or (Blob $debug) -ne $expectedDebug) {
    throw 'HELPER_STAGING_FAILED'
  }
  $stage='RUN_LOCAL_SERVICE_DIAGNOSTIC'
  $item=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Слэмбол 6 кг')).TrimEnd('=').Replace('+','-').Replace('/','_')
  $warehouse=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Основной склад')).TrimEnd('=').Replace('+','-').Replace('/','_')
  $identity=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $job=$scheduler.NewTask(0)
  $job.RegistrationInfo.Description='Once: strictly read-only sanitized NewBase name-and-warehouse diagnostic'
  $job.Principal.UserId=$identity
  $job.Principal.LogonType=5
  $job.Principal.RunLevel=0
  $job.Settings.Enabled=$true
  $job.Settings.AllowDemandStart=$true
  $job.Settings.StartWhenAvailable=$false
  $job.Settings.ExecutionTimeLimit='PT4M'
  $step=$job.Actions.Create(0)
  $step.Path=Join-Path $PSHOME 'powershell.exe'
  $step.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$debug+
    '" -Kind name -ItemB64 '+$item+' -WarehouseB64 '+$warehouse)
  $register=$folder.RegisterTaskDefinition($taskName,$job,2,$identity,$null,5,$null)
  if ($null -eq $register) { throw 'TASK_REGISTER_FAILED' }
  $registered=$true
  if ($folder.GetTask($taskName).Definition.Triggers.Count -ne 0) {
    throw 'TASK_HAS_TRIGGER'
  }
  $started=[DateTime]::UtcNow
  $null=$register.Run($null)
  $found=$false
  for($i=0;$i -lt 115;$i++) {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $report -PathType Leaf) {
      $file=Get-Item -LiteralPath $report
      if ($file.Length -le 500 -and $file.LastWriteTimeUtc -ge $started) {
        $found=$true
        break
      }
    }
  }
  if (-not $found) { throw 'NO_DIAGNOSTIC_RECEIPT' }
  $raw=[IO.File]::ReadAllText($report,[Text.Encoding]::ASCII)
  $lines=@($raw -split '[\r\n]+' | Where-Object {$_})
  if ($lines.Count -lt 2 -or $lines.Count -gt 4) { throw 'BAD_RECEIPT_SIZE' }
  foreach($line in $lines) {
    if ($line -notmatch '^(STAGE=[A-Z_]{1,60}|REASON=[A-Z0-9_]{1,60}|ERROR_TYPE=[A-Za-z]{1,45}|RESULT=(PASS|FAIL))$') {
      throw 'UNSAFE_RECEIPT_REJECTED'
    }
    Write-Output $line
  }
  Write-Output 'OPERATING_AGENT_UNCHANGED=YES'
} catch {
  $code=$_.Exception.Message
  if ($code -notmatch '^[A-Z0-9_]{1,60}$') {$code='UNKNOWN'}
  Write-Output ('DIAGNOSTIC=FAIL;STAGE='+$stage+';CODE='+$code)
  Write-Output 'OPERATING_AGENT_UNCHANGED=YES'
} finally {
  if ($registered -and $null -ne $folder) {
    try {
      $task=$folder.GetTask($taskName)
      if ($task.State -eq 4) { $task.Stop(0) }
      $folder.DeleteTask($taskName,0)
      Write-Output 'TEMPORARY_TASK_CLEANUP=PASS'
    } catch { Write-Output 'TEMPORARY_TASK_CLEANUP=RECHECK' }
  }
  if ($installed -and (Test-Path -LiteralPath $debug -PathType Leaf)) {
    try { Remove-Item -LiteralPath $debug -Force -ErrorAction Stop }
    catch { Write-Output 'DIAGNOSTIC_HELPER_CLEANUP=RECHECK' }
  }
  if (Test-Path -LiteralPath $staged -PathType Leaf) {
    Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
  }
}

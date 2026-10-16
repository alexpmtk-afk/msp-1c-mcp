#requires -version 2
# Admin-only one-shot V2 diagnostic, using untouched verified original
# failed V2 stage. NO active agent/source replacement and NO 1C writes.
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$active=Join-Path $bin 'onec-system-probe-poll.ps1'
$lib=Join-Path $bin 'onec-legacy-json.ps1'
$helper=Join-Path $bin 'onec-natural-diagnostic-helper-v2.ps1'
$receipt=Join-Path $state 'natural-stock-v2-diagnostic-result.txt'
$previousReport=Join-Path $state 'natural-stock-live-smoke.txt'
$v2stage=Join-Path $env:TEMP 'OnecNaturalAgentCutover_V2_20261015'
$source=Join-Path $v2stage 'onec-legacy-json.ps1'
$curl=Join-Path $bin 'curl.exe'
$ca=Join-Path $bin 'curl-ca-bundle.crt'
$taskName='MspOnecNaturalV2DiagnosticOnce'
$expectedLive='c7ad87b2d6ec41b0124a083d1bdf3305f5aee71f'
$expectedJson='05a3939ed2b8eb28378b395fc8a1b52989b5c3d5'
$expectedHelper='0311d1a3a6e3f22babe8aa91383f35e0bd035073'
$commit='c5ee98bdf20362f662e00e317d6e42481b278dc6'
$tempFile=Join-Path $env:TEMP ('onec-natural-v2-debug-'+[Guid]::NewGuid().ToString('N')+'.ps1')
$folder=$null
$taskCreated=$false
$helperInstalled=$false
$jsonInstalled=$false
$stage='PREFLIGHT'
function GitBlob([string]$path) {
  [byte[]]$data=[IO.File]::ReadAllBytes($path)
  [byte[]]$head=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length+[char]0))
  $ms=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $ms.Write($head,0,$head.Length)
    $ms.Write($data,0,$data.Length)
    $ms.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($ms))).Replace('-','').ToLowerInvariant()
  } finally { $ms.Close(); $sha.Clear() }
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
  foreach($file in @($active,$source,$previousReport,$curl,$ca)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'REQUIRED_FILE_MISSING' }
  }
  if ((GitBlob $active) -ne $expectedLive) { throw 'ACTIVE_AGENT_CHANGED' }
  if ((GitBlob $source) -ne $expectedJson) { throw 'V2_JSON_SOURCE_CHANGED' }
  if (([IO.File]::ReadAllText($previousReport,[Text.Encoding]::UTF8).Trim()) -cne
      ('ONEC_NATURAL_STOCK_LIVE_SMOKE'+[Environment]::NewLine+'RESULT=FAIL')) {
    throw 'PREVIOUS_REPORT_CHANGED'
  }
  foreach($file in @($lib,$helper,$receipt)) {
    if (Test-Path -LiteralPath $file) { throw 'DIAGNOSTIC_ALREADY_PRESENT' }
  }
  $sched=New-Object -ComObject 'Schedule.Service'
  $sched.Connect()
  $folder=$sched.GetFolder('\')
  foreach($t in $folder.GetTasks(0)) {
    if ($t.Name -eq $taskName) { throw 'TASK_ALREADY_PRESENT' }
  }

  $stage='STAGE_FIXED_JSON'
  Copy-Item -LiteralPath $source -Destination $lib -ErrorAction Stop
  $jsonInstalled=$true
  if ((GitBlob $lib) -ne $expectedJson) { throw 'STAGED_JSON_MISMATCH' }
  $stage='DOWNLOAD_PINNED_DIAGNOSTIC'
  $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/'+$commit+'/scripts/windows/onec-natural-diagnostic-helper-v2.ps1'
  $curlArgs=@('-q','--fail','--silent','--show-error','--noproxy','*',
    '--tlsv1.2','--tls-max','1.2','--proto','=https','--max-redirs','0',
    '--cacert',$ca,'--connect-timeout','15','--max-time','45','--output',$tempFile,$url)
  & $curl @curlArgs | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempFile -PathType Leaf)) {
    throw 'DOWNLOAD_FAILED'
  }
  if ((GitBlob $tempFile) -ne $expectedHelper) { throw 'SOURCE_HASH_MISMATCH' }
  $parseErrors=$null
  $sourceText=[IO.File]::ReadAllText($tempFile,[Text.Encoding]::UTF8)
  $null=[Management.Automation.PSParser]::Tokenize($sourceText,[ref]$parseErrors)
  if ($parseErrors -and $parseErrors.Count -gt 0) { throw 'PS2_PARSE_FAILED' }
  if (-not $sourceText.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) {
    throw 'SOURCE_GUARD_MISSING'
  }
  Copy-Item -LiteralPath $tempFile -Destination $helper -ErrorAction Stop
  $helperInstalled=$true
  if ((GitBlob $helper) -ne $expectedHelper) { throw 'HELPER_HASH_CHANGED' }
  $ic=Join-Path $env:WINDIR 'System32\icacls.exe'
  & $ic $lib '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'JSON_ACL_FAILED' }
  & $ic $helper '/reset' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'HELPER_ACL_FAILED' }

  $stage='RUN_LOCAL_SERVICE_DIAGNOSTIC'
  $item=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Слэмбол 6 кг')).TrimEnd('=').Replace('+','-').Replace('/','_')
  $warehouse=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Основной склад')).TrimEnd('=').Replace('+','-').Replace('/','_')
  $localService=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
  $job=$sched.NewTask(0)
  $job.RegistrationInfo.Description='One-time read-only staged V2 failure classification'
  $job.Principal.UserId=$localService
  $job.Principal.LogonType=5
  $job.Principal.RunLevel=0
  $job.Settings.Enabled=$true
  $job.Settings.AllowDemandStart=$true
  $job.Settings.StartWhenAvailable=$false
  $job.Settings.ExecutionTimeLimit='PT4M'
  $action=$job.Actions.Create(0)
  $action.Path=Join-Path $PSHOME 'powershell.exe'
  $action.Arguments=('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+
     $helper+'" -Kind name -ItemB64 '+$item+' -WarehouseB64 '+$warehouse)
  $registered=$folder.RegisterTaskDefinition($taskName,$job,2,$localService,$null,5,$null)
  if ($null -eq $registered) { throw 'TASK_REGISTER_FAILED' }
  $taskCreated=$true
  if ($folder.GetTask($taskName).Definition.Triggers.Count -ne 0) {
    throw 'UNEXPECTED_TASK_TRIGGER'
  }
  $started=[DateTime]::UtcNow
  $null=$registered.Run($null)
  $ready=$false
  for($i=0;$i -lt 115;$i++) {
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $receipt -PathType Leaf) {
      $file=Get-Item -LiteralPath $receipt
      if ($file.Length -le 400 -and $file.LastWriteTimeUtc -ge $started) {
        $ready=$true;break
      }
    }
  }
  if (-not $ready) { throw 'NO_DIAGNOSTIC_RESULT' }
  $output=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII)
  $lines=@($output -split '[\r\n]+' | Where-Object {$_})
  if ($lines.Count -ne 4) { throw 'INVALID_RESULT_LINE_COUNT' }
  if ($lines[0] -notmatch '^STAGE=[A-Z_]{1,60}$' -or
      $lines[1] -notmatch '^REASON=[A-Z0-9_]{1,60}$' -or
      $lines[2] -notmatch '^ERROR_TYPE=[A-Za-z]{1,45}$' -or
      $lines[3] -notmatch '^RESULT=(PASS|FAIL)$') {
    throw 'INVALID_RESULT_CONTENT'
  }
  foreach($line in $lines){Write-Output $line}
  Write-Output 'OPERATING_AGENT_UNCHANGED=YES'
} catch {
  $code=$_.Exception.Message
  if ($code -notmatch '^[A-Z0-9_]{1,60}$') { $code='DIAGNOSTIC_ERROR' }
  Write-Output ('DIAGNOSTIC=FAIL;STAGE='+$stage+';CODE='+$code)
  Write-Output 'OPERATING_AGENT_UNCHANGED=YES'
} finally {
  if ($taskCreated -and $null -ne $folder) {
    try {
      $current=$folder.GetTask($taskName)
      if ($current.State -eq 4) { $current.Stop(0) }
      $folder.DeleteTask($taskName,0)
      Write-Output 'TEMPORARY_TASK_CLEANUP=PASS'
    } catch { Write-Output 'TEMPORARY_TASK_CLEANUP=RECHECK' }
  }
  if ($helperInstalled -and (Test-Path -LiteralPath $helper -PathType Leaf)) {
    Remove-Item -LiteralPath $helper -Force -ErrorAction SilentlyContinue
  }
  if ($jsonInstalled -and (Test-Path -LiteralPath $lib -PathType Leaf)) {
    Remove-Item -LiteralPath $lib -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $tempFile -PathType Leaf) {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
  }
}

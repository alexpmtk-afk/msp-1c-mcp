#requires -version 2
# Triggerless LocalService probe of the INSTALLED child-helper stdout boundary.
# Never changes agent/1C, enqueues jobs, logs raw records or exposes credentials.
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$receipt=Join-Path $state 'natural-stock-installed-child-shape-v3.txt'
$helper=Join-Path $bin 'onec-system-odata-natural.ps1'
$agent=Join-Path $bin 'onec-system-probe-poll.ps1'
$json=Join-Path $bin 'onec-legacy-json.ps1'
$writer=Join-Path $bin 'onec-natural-stock-json-writer.ps1'
$exitZero='NOT_RUN'
$stdoutTotal=0
$natTotal=0
$natStatus='NOT_RUN'
$natTwo='NOT_RUN'
$extraAscii=0
$extraNonAscii=0
$extraBlank=0
$extraShort=0
$extraMedium=0
$extraLong=0
$extraDiagnostic=0
$extraJsonLike=0
$extraTypeLike=0
$extraNumeric=0
$stage='START'
function Blob([string]$file) {
  [byte[]]$raw=[IO.File]::ReadAllBytes($file)
  [byte[]]$header=[Text.Encoding]::ASCII.GetBytes(('blob '+$raw.Length+[char]0))
  $stream=New-Object IO.MemoryStream
  $sha=[Security.Cryptography.SHA1]::Create()
  try {
    $stream.Write($header,0,$header.Length)
    $stream.Write($raw,0,$raw.Length)
    $stream.Position=0
    return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
  } finally { $sha.Clear();$stream.Close() }
}
try {
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19' -or
      $PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_CONTEXT' }
  if (Test-Path -LiteralPath $receipt -PathType Leaf) { throw 'EXISTING_RECEIPT' }
  $stage='VERIFY_INSTALLED_SOURCES'
  foreach($pair in @(
    @($agent,'006a0b618575b4ab3a00b54c2863a436841e00ed'),
    @($helper,'08c23d0d6316ba7ddf1fd3e0f62e3269314838c7'),
    @($json,'05a3939ed2b8eb28378b395fc8a1b52989b5c3d5'),
    @($writer,'981a2e1ec0404b4afc42f0e35432f7cfbcde8e8a'))) {
      if (-not (Test-Path -LiteralPath $pair[0] -PathType Leaf) -or
          (Blob $pair[0]) -ne $pair[1]) { throw 'INSTALLED_HASH_MISMATCH' }
  }
  $stage='INVOKE_INSTALLED_HELPER'
  $item=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Слэмбол 6 кг')).TrimEnd('=').Replace('+','-').Replace('/','_')
  $warehouse=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Основной склад')).TrimEnd('=').Replace('+','-').Replace('/','_')
  $output=@(& (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -Kind name -ItemB64 $item -WarehouseB64 $warehouse 2>$null)
  $exitZero=$(if ($LASTEXITCODE -eq 0) {'YES'}else{'NO'})
  $stdoutTotal=$output.Count
  $stage='CLASSIFY_STDOUT_ONLY'
  $tokenValue=$null
  foreach($entry in $output) {
    if ($entry -is [string] -and $entry -match '^NAT_([A-Za-z0-9_-]{3,360000})$') {
      $natTotal++
      if ($natTotal -eq 1) { $tokenValue=$Matches[1] }
      continue
    }
    if ($null -eq $entry -or -not ($entry -is [string])) {
      $extraBlank++
      continue
    }
    $value=[string]$entry
    if ($value.Trim().Length -eq 0) { $extraBlank++ }
    if ($value.Length -le 12) { $extraShort++ }
    elseif ($value.Length -le 100) { $extraMedium++ }
    else { $extraLong++ }
    if ($value -match '^[\x00-\x7f]*$') { $extraAscii++ }
    else { $extraNonAscii++ }
    if ($value -match '(?i)warning|add-type|exception|compil|error|powershell|copyright') {
      $extraDiagnostic++
    }
    if ($value -match '^\s*[\{\[]') { $extraJsonLike++ }
    if ($value -match '^System\.[A-Za-z0-9_.+]{1,120}$') { $extraTypeLike++ }
    if ($value -match '^-?[0-9]{1,12}(\.[0-9]{1,5})?$') { $extraNumeric++ }
  }
  if ($natTotal -eq 1) {
    $stage='CLASSIFY_ENCODED_JSON_STATUS'
    $token=$tokenValue.Replace('-','+').Replace('_','/')
    $token+=('='*((4-$token.Length%4)%4))
    [byte[]]$bytes=[Convert]::FromBase64String($token)
    if ($bytes.Length -gt 262144) { throw 'PAYLOAD_TOO_LARGE' }
    $jsonBody=[Text.Encoding]::UTF8.GetString($bytes)
    if ($jsonBody -match '^\{"status":"PASS",') { $natStatus='PASS' }
    elseif ($jsonBody -ceq '{"status":"UNAVAILABLE"}') { $natStatus='UNAVAILABLE' }
    else { $natStatus='OTHER' }
    if ($natStatus -eq 'PASS' -and $jsonBody -match '"match_count":2[,}]') {
      $natTwo='CLAIMED_TWO'
    } else { $natTwo='NOT_CONFIRMED' }
  }
  $stage='COMPLETED'
} catch {
  if ($stage -eq 'START') { $stage='PREFLIGHT_FAIL' }
  elseif ($stage -eq 'VERIFY_INSTALLED_SOURCES') { $stage='HASH_FAIL' }
  elseif ($stage -eq 'INVOKE_INSTALLED_HELPER') { $stage='INVOKE_FAIL' }
  else { $stage='OUTPUT_FAIL' }
} finally {
  if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    [string[]]$lines=New-Object string[] 16
    $lines[0]='STAGE='+$stage
    $lines[1]='CHILD_EXIT_ZERO='+$exitZero
    $lines[2]='STDOUT_COUNT='+$stdoutTotal
    $lines[3]='NAT_COUNT='+$natTotal
    $lines[4]='NAT_STATUS='+$natStatus
    $lines[5]='NAT_TWO_CARDS='+$natTwo
    $lines[6]='EXTRA_ASCII='+$extraAscii
    $lines[7]='EXTRA_NONASCII='+$extraNonAscii
    $lines[8]='EXTRA_BLANK='+$extraBlank
    $lines[9]='EXTRA_SHORT='+$extraShort
    $lines[10]='EXTRA_MEDIUM='+$extraMedium
    $lines[11]='EXTRA_LONG='+$extraLong
    $lines[12]='EXTRA_DIAGNOSTIC_LIKE='+$extraDiagnostic
    $lines[13]='EXTRA_JSON_LIKE='+$extraJsonLike
    $lines[14]='EXTRA_TYPE_LIKE='+$extraTypeLike
    $lines[15]='EXTRA_NUMERIC='+$extraNumeric
    try { [IO.File]::WriteAllLines($receipt,$lines,[Text.Encoding]::ASCII) }
    catch {}
  }
}

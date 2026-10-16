#requires -version 2
# Triggerless LocalService probe of the INSTALLED child-helper stdout boundary.
# Never changes agent/1C, enqueues jobs, logs raw records or exposes credentials.
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$bin=Join-Path $root 'bin'
$state=Join-Path $root 'state'
$receipt=Join-Path $state 'natural-stock-installed-child-shape-v2.txt'
$helper=Join-Path $bin 'onec-system-odata-natural.ps1'
$agent=Join-Path $bin 'onec-system-probe-poll.ps1'
$json=Join-Path $bin 'onec-legacy-json.ps1'
$writer=Join-Path $bin 'onec-natural-stock-json-writer.ps1'
$exitZero='NOT_RUN'
$total='NOT_RUN'
$natCount='NOT_RUN'
$natStatus='NOT_RUN'
$natCards='NOT_RUN'
$otherShort=0
$otherMedium=0
$otherLong=0
$otherNonString=0
$otherEmpty=0
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
  $total=[string]$output.Count
  $stage='CLASSIFY_STDOUT_SHAPE'
  $natCount=0
  $natPayload=$null
  foreach($entry in $output) {
    if ($entry -is [string] -and $entry -match '^NAT_([A-Za-z0-9_-]{3,360000})$') {
      $natCount++
      if ($natCount -eq 1) { $natPayload=$Matches[1] }
    } elseif ($null -eq $entry) {
      $otherEmpty++
    } elseif (-not ($entry -is [string])) {
      $otherNonString++
    } elseif ($entry.Length -eq 0) {
      $otherEmpty++
    } elseif ($entry.Length -le 12) {
      $otherShort++
    } elseif ($entry.Length -le 100) {
      $otherMedium++
    } else {
      $otherLong++
    }
  }
  $natCount=[string]$natCount
  if ($natCount -eq '1') {
    $stage='DECODE_ONE_NAT_ENVELOPE'
    $token=$natPayload.Replace('-','+').Replace('_','/')
    $token+=('='*((4-$token.Length%4)%4))
    [byte[]]$bytes=[Convert]::FromBase64String($token)
    if ($bytes.Length -gt 262144) { throw 'PAYLOAD_TOO_LARGE' }
    . $json
    $parser=New-Object MspLegacyJson
    $data=$parser.DeserializeObject([Text.Encoding]::UTF8.GetString($bytes))
    $status=[string]$data['status']
    $natStatus=$(if ($status -eq 'PASS') {'PASS'}elseif ($status -eq 'UNAVAILABLE') {'UNAVAILABLE'}else{'OTHER'})
    $natCards=$(if($data.ContainsKey('items') -and @($data['items']).Count -eq 2){'TWO'}else{'OTHER'})
  }
  $stage='COMPLETED'
} catch {
  if ($stage -eq 'START') { $stage='PREFLIGHT_FAIL' }
  elseif ($stage -eq 'VERIFY_INSTALLED_SOURCES') { $stage='HASH_FAIL' }
  elseif ($stage -eq 'INVOKE_INSTALLED_HELPER') { $stage='INVOKE_FAIL' }
  else { $stage='OUTPUT_FAIL' }
} finally {
  if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    $safe=(@('STAGE='+$stage,'CHILD_EXIT_ZERO='+$exitZero,
      'STDOUT_ITEM_COUNT='+$total,'NAT_ITEM_COUNT='+$natCount,
      'NAT_STATUS='+$natStatus,'NAT_CARD_COUNT='+$natCards,
      'OTHER_SHORT='+$otherShort,'OTHER_MEDIUM='+$otherMedium,
      'OTHER_LONG='+$otherLong,'OTHER_NONSTRING='+$otherNonString,
      'OTHER_EMPTY='+$otherEmpty) -join [Environment]::NewLine)
    try {[IO.File]::WriteAllText($receipt,$safe,[Text.Encoding]::ASCII)} catch {}
  }
}

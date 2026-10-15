#requires -version 2
# Read-only manual LocalService acceptance of the newly staged fixed helper.
# This runner outputs only cardinality/quantity acceptance flags (no GUIDs).
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$helper=Join-Path (Join-Path $root 'bin') 'onec-system-odata-natural.ps1'
$report=Join-Path (Join-Path $root 'state') 'natural-stock-live-smoke.txt'
$lines=New-Object 'System.Collections.Generic.List[string]'
[void]$lines.Add('ONEC_NATURAL_STOCK_LIVE_SMOKE')
try {
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') {
    throw 'WRONG_IDENTITY'
  }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_POWERSHELL' }
  if (Test-Path -LiteralPath $report) { throw 'EXISTING_RECEIPT' }
  if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
    throw 'HELPER_NOT_STAGED'
  }
  $name='Слэмбол 6 кг'
  $warehouse='Основной склад'
  $itemToken=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($name)).TrimEnd('=').Replace('+','-').Replace('/','_')
  $warehouseToken=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($warehouse)).TrimEnd('=').Replace('+','-').Replace('/','_')
  $output=@(& (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -Kind name -ItemB64 $itemToken -WarehouseB64 $warehouseToken)
  if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or
      [string]$output[0] -notmatch '^NAT_([A-Za-z0-9_-]{3,360000})$') {
    throw 'HELPER_DID_NOT_PASS'
  }
  $value=$Matches[1].Replace('-','+').Replace('_','/')
  $value=$value+('=' * ((4-$value.Length%4)%4))
  $bytes=[Convert]::FromBase64String($value)
  if ($bytes.Length -gt 262144) { throw 'OVERSIZED_RESULT' }
  $jsonLibrary=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'onec-legacy-json.ps1'
  if (-not (Test-Path -LiteralPath $jsonLibrary -PathType Leaf)) { throw 'JSON_LIB_NOT_INSTALLED' }
  . $jsonLibrary
  $serializer=New-Object MspLegacyJson
  $serializer.MaxJsonLength=262144
  $data=$serializer.DeserializeObject([Text.Encoding]::UTF8.GetString($bytes))
  if ($data['status'] -ne 'PASS' -or [int]$data['match_count'] -ne 2 -or
      $data['search_kind'] -ne 'name' -or $data['search_term'] -cne $name -or
      $data['requested_warehouse'] -cne $warehouse) {
    throw 'WRONG_ACCEPTANCE_RESPONSE'
  }
  $items=@($data['items'])
  if ($items.Count -ne 2) { throw 'WRONG_ITEM_COUNT' }
  $expectedA=$false;$expectedB=$false
  foreach($row in $items) {
    if ($row['name'] -cne $name -or
        ($null -ne $row['article'] -and [string]$row['article'] -ne '')) {
      throw 'WRONG_NAME_OR_ARTICLE'
    }
    if ($row['code'] -eq 'НФ-00001359' -and $row['total_quantity'] -eq '6' -and
        $row['balance_state'] -eq 'HAS_BALANCE_ROWS') {
      $cells=@($row['warehouses'])
      if ($cells.Count -ne 1 -or $cells[0]['name'] -cne $warehouse -or
          $cells[0]['quantity'] -ne '6' -or
          $cells[0]['balance_state'] -ne 'ROW_PRESENT') {
        throw 'WRONG_FIRST_BALANCE_ROW'
      }
      $expectedA=$true
    } elseif ($row['code'] -eq 'НФ-00000879' -and $row['total_quantity'] -eq '0' -and
              $row['balance_state'] -eq 'NO_BALANCE_ROW') {
      $cells=@($row['warehouses'])
      if ($cells.Count -ne 1 -or $cells[0]['name'] -cne $warehouse -or
          $cells[0]['quantity'] -ne '0' -or
          $cells[0]['balance_state'] -ne 'NO_BALANCE_ROW') {
        throw 'WRONG_SECOND_BALANCE_ROW'
      }
      $expectedB=$true
    } else {
      throw 'UNKNOWN_DUPLICATE_CARD'
    }
  }
  if (-not $expectedA -or -not $expectedB) { throw 'MISSING_EXPECTED_ITEM' }
  [void]$lines.Add('PRODUCT_NAME_MATCHES=2')
  [void]$lines.Add('WAREHOUSE_NAME_EXACT=YES')
  [void]$lines.Add('OBSERVED_STOCK_6=PASS')
  [void]$lines.Add('MISSING_BALANCE_QUALIFIED_ZERO=PASS')
  [void]$lines.Add('RESULT=PASS')
  [IO.File]::WriteAllText($report,($lines -join [Environment]::NewLine),[Text.Encoding]::UTF8)
  exit 0
} catch {
  $failure='ONEC_NATURAL_STOCK_LIVE_SMOKE'+[Environment]::NewLine+'RESULT=FAIL'
  try {
    if (-not (Test-Path -LiteralPath $report)) {
      [IO.File]::WriteAllText($report,$failure,[Text.Encoding]::UTF8)
    }
  } catch {}
  exit 1
}

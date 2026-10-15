#requires -version 2
# Dedicated manual-only LocalService ONE-SHOT diagnostic for NewBase metadata.
# No network calls except those made by the fixed GET-only local helper.
# No secrets, raw product names or GUIDs are written to the report.
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$helper=Join-Path (Join-Path $root 'bin') 'onec-natural-stock-schema-preflight.ps1'
$report=Join-Path (Join-Path $root 'state') 'natural-stock-schema-report.txt'
$safe=New-Object 'System.Collections.Generic.List[string]'
try {
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') {
    throw 'NOT_LOCAL_SERVICE'
  }
  if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'HELPER_MISSING' }
  $ps=Join-Path $PSHOME 'powershell.exe'
  $lines=@(& $ps -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper)
  $success=($LASTEXITCODE -eq 0 -and $lines -contains 'RESULT=PASS')
  $null=$safe.Add('ONEC_NATURAL_STOCK_ONESHOT_RESULT')
  foreach($line in $lines) {
    if ($null -eq $line) { continue }
    $text=[string]$line
    if ($text.Length -gt 180) { continue }
    if ($text -match '^(?:ITEM_CATALOG_PRESENT|ARTICLE_FIELD_PRESENT|CODE_FIELD_PRESENT|BALANCE_ENTITY_PRESENT|BALANCE_ITEM_KEY_PRESENT|BALANCE_WAREHOUSE_KEY_PRESENT|BALANCE_QUANTITY_PRESENT|WAREHOUSE_HAS_REF_KEY|WAREHOUSE_HAS_DESCRIPTION|ODATA_GET_ONLY|DATA_WRITES|RAW_NOMENCLATURE_AND_GUIDS_EXPORTED|RAW_CUSTOMERS_OR_CREDENTIALS_EXPORTED)=(YES|NO)$' -or
        $text -match '^NAME_FIELD=(Description|Наименование|NOT_VERIFIED)$' -or
        $text -match '^WAREHOUSE_ENTITY_CANDIDATE_COUNT=[0-9]{1,2}$' -or
        $text -match '^ARTICLE_FIELD_CANDIDATE_COUNT=[0-9]{1,2}$' -or
        $text -match '^WAREHOUSE_ENTITY=Catalog_(СтруктурныеЕдиницы|Склады|СкладскиеПомещения|СкладыКомпании)$' -or
        $text -match '^ARTICLE_FIELD_CANDIDATE=[A-Za-zА-Яа-яЁё0-9_]{1,80}$' -or
        $text -match '^EXAMPLE_(ARTICLE|CODE)_MATCHES=(NOT_TESTED|ZERO|ONE|TWO_OR_MORE)$' -or
        $text -eq 'ODATA_METADATA_GET=PASS') {
      $null=$safe.Add($text)
    }
  }
  $null=$safe.Add('RESULT='+$(if($success){'PASS'}else{'FAIL'}))
  [IO.File]::WriteAllText($report,($safe -join [Environment]::NewLine),[Text.Encoding]::UTF8)
  if(-not $success) { exit 1 }
  exit 0
} catch {
  $default='ONEC_NATURAL_STOCK_ONESHOT_RESULT'+[Environment]::NewLine+'RESULT=FAIL'
  try { [IO.File]::WriteAllText($report,$default,[Text.Encoding]::UTF8) } catch {}
  exit 1
}

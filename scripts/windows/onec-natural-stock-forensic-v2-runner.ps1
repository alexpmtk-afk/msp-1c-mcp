#requires -version 2
# Forensic follow-up, read-only: call the already installed, SHA-verified
# LocalService NewBase OData metadata helper; record only phase/status codes.
# Does NOT change any installed helper, agent, scheduler or 1C data.
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$helper=Join-Path (Join-Path $root 'bin') 'onec-natural-stock-schema-preflight.ps1'
$report=Join-Path (Join-Path $root 'state') 'natural-stock-schema-report-v2.txt'
$status='RUNNER_ERROR'
$phase='NOT_EXECUTED'
$rows=New-Object 'System.Collections.Generic.List[string]'
try {
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') {
    throw 'WRONG_IDENTITY'
  }
  if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'HELPER_MISSING' }
  $ps=Join-Path $PSHOME 'powershell.exe'
  $lines=@(& $ps -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper)
  $exitCode=$LASTEXITCODE
  $status='PROBE_FAILED'
  $phase='NO_CLASSIFIED_STAGE'
  $complete=($exitCode -eq 0 -and $lines -contains 'RESULT=PASS')
  $rows.Add('ONEC_NATURAL_STOCK_FORENSIC_V2') | Out-Null
  foreach($line in $lines) {
    if ($null -eq $line) { continue }
    $value=[string]$line
    if ($value.Length -gt 190) { continue }
    # Allow only known literal status codes; never forward the raw script
    # exception, GUID, OData XML, product record or credential.
    if ($value -match '^RESULT=FAIL;STAGE=(PRECHECK|SCHEMA_GET|EXACT_ARTICLE_FILTER);DETAILS=REDACTED$') {
      $phase=$Matches[1]
    }
    if ($complete) {
      if ($value -match '^(?:ITEM_CATALOG_PRESENT|ARTICLE_FIELD_PRESENT|CODE_FIELD_PRESENT|BALANCE_ENTITY_PRESENT|BALANCE_ITEM_KEY_PRESENT|BALANCE_WAREHOUSE_KEY_PRESENT|BALANCE_QUANTITY_PRESENT|WAREHOUSE_HAS_REF_KEY|WAREHOUSE_HAS_DESCRIPTION|ODATA_GET_ONLY|DATA_WRITES|RAW_NOMENCLATURE_AND_GUIDS_EXPORTED|RAW_CUSTOMERS_OR_CREDENTIALS_EXPORTED)=(YES|NO)$' -or
          $value -match '^NAME_FIELD=(Description|Наименование|NOT_VERIFIED)$' -or
          $value -match '^WAREHOUSE_ENTITY_CANDIDATE_COUNT=[0-9]{1,2}$' -or
          $value -match '^ARTICLE_FIELD_CANDIDATE_COUNT=[0-9]{1,2}$' -or
          $value -match '^WAREHOUSE_ENTITY=Catalog_(СтруктурныеЕдиницы|Склады|СкладскиеПомещения|СкладыКомпании)$' -or
          $value -match '^ARTICLE_FIELD_CANDIDATE=[A-Za-zА-Яа-яЁё0-9_]{1,80}$' -or
          $value -match '^EXAMPLE_(ARTICLE|CODE)_MATCHES=(NOT_TESTED|ZERO|ONE|TWO_OR_MORE)$') {
        $rows.Add($value) | Out-Null
      }
    }
  }
  if ($complete) { $status='PASS'; $phase='COMPLETE' }
  $rows.Add('PROBE_PHASE='+$phase) | Out-Null
  $rows.Add('PROBE_RESULT='+$status) | Out-Null
  [IO.File]::WriteAllText($report,($rows -join [Environment]::NewLine),[Text.Encoding]::UTF8)
  if ($status -ne 'PASS') { exit 1 }
  exit 0
} catch {
  $output='ONEC_NATURAL_STOCK_FORENSIC_V2'+[Environment]::NewLine+
          'PROBE_PHASE=RUNNER_FAILURE'+[Environment]::NewLine+
          'PROBE_RESULT=RUNNER_ERROR'
  try { [IO.File]::WriteAllText($report,$output,[Text.Encoding]::UTF8) } catch {}
  exit 1
}

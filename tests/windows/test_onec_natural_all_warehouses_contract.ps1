#requires -version 2
# Offline source contract for the physical WinServer2008R2/PowerShell2
# mandatory-argument '-' failure. Does not execute SRV helper, OData or queue.
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..')).Path
$pollerPath=Join-Path $root 'scripts\windows\onec-system-probe-poll.ps1'
$helperPath=Join-Path $root 'scripts\windows\onec-system-odata-natural.ps1'
$poller=[IO.File]::ReadAllText($pollerPath,[Text.Encoding]::UTF8)
$helper=[IO.File]::ReadAllText($helperPath,[Text.Encoding]::UTF8)
$expected='-WarehouseB64 $(if($naturalWarehouse -eq ''-''){''ALL''}else{$naturalWarehouse})'
if (-not $poller.Contains($expected)) { throw 'MISSING_CHILD_ALL_ARGUMENT_MAP' }
if ($poller.Contains('-WarehouseB64 $naturalWarehouse')) { throw 'OLD_DASH_ARGUMENT_REGRESSION' }
if ($poller.Contains("Replace('-','ALL')")) { throw 'UNSAFE_GLOBAL_DASH_REPLACEMENT' }
$guard='if ($WarehouseB64 -ne ''-'' -and $WarehouseB64 -ne ''ALL'')'
if (-not $helper.Contains($guard)) { throw 'HELPER_ALL_DECODE_GUARD_MISSING' }
if (-not $helper.Contains('[Parameter(Mandatory=$true)][string]$WarehouseB64')) {
  throw 'MANDATORY_WAREHOUSE_CONTRACT_CHANGED'
}
foreach($p in @($pollerPath,$helperPath)) {
  $source=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)
  $errors=$null
  $null=[Management.Automation.PSParser]::Tokenize($source,[ref]$errors)
  if ($errors -and $errors.Count -gt 0) { throw 'PS2_PARSE_FAILED' }
}
function Map-Warehouse([string]$warehouse) {
  return $(if($warehouse -eq '-'){'ALL'}else{$warehouse})
}
if ((Map-Warehouse '-') -cne 'ALL') { throw 'UNSPECIFIED_WAREHOUSE_NOT_MAPPED' }
foreach($valid in @('QUJD-REVG','QUJD_REVG','ALL','TWFpbg')) {
  if ((Map-Warehouse $valid) -cne $valid) { throw 'REAL_WAREHOUSE_TOKEN_CHANGED' }
}
if ('ALL' -ne '-' -and 'ALL' -ne 'ALL') { throw 'HELPER_ALL_GUARD_FAILED' }
if ('QUJD-REVG' -eq '-' -or 'QUJD-REVG' -eq 'ALL') { throw 'HELPER_REAL_WAREHOUSE_GUARD_FAILED' }
'ONEC_CHILD_ALL_SENTINEL_SOURCE_AND_MAPPING=PASS'
'PHYSICAL_PS2_DASH_REPRODUCTION=IN_HANDOFF_20261016_NOT_CI'

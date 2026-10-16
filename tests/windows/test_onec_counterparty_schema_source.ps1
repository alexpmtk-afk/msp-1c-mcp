#requires -version 2
# Offline, no SRV/1C connection. Parse and guard the metadata-only probe.
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..')).Path
$file=Join-Path $root 'scripts\windows\onec-counterparty-schema-preflight.ps1'
[byte[]]$bytes=[IO.File]::ReadAllBytes($file)
if ($bytes.Length -lt 6 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw 'UTF8_BOM_REQUIRED_FOR_PS2' }
$source=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
if (-not $source.TrimStart([char]0xFEFF).StartsWith('#requires -version 2')) { throw 'PS2_REQUIRED' }
$errors=$null
$null=[Management.Automation.PSParser]::Tokenize($source,[ref]$errors)
if ($errors -and $errors.Count -gt 0) { throw 'PS2_PARSE_FAIL' }
foreach($token in @('S-1-5-19','MCP_OData_ReadOnly','ProtectedData]::Unprotect',
    '127.0.0.1:8085/NewBase/odata/standard.odata/',
    "'$"+'metadata'+"'", "Method='GET'",'AllowAutoRedirect=$false',
    'ProhibitDtd=$true','XmlResolver=$null','MaxCharactersInDocument',
    'Catalog_Контрагенты','Catalog_Партнеры','Catalog_Организации',
    "Ref_Key",'Description','READ_ACCESS=','RECORD_DATA_EXPORTED=NO',
    'CREDENTIALS_EXPORTED=NO','NEW_MCP_ENABLED=NO')) {
  if (-not $source.Contains($token)) { throw ('MISSING_BOUNDARY='+$token) }
}
foreach($blocked in @('Invoke-Expression','Invoke-RestMethod','Invoke-Command',
   'Start-Process','RegisterTaskDefinition','New-ScheduledTask','Set-Acl',
   'Restart-Service','Start-Service','HttpListener','WebClient','POST','PUT','DELETE')) {
  if ($source -cmatch ('\b'+[regex]::Escape($blocked)+'\b')) { throw ('UNSAFE_OPERATION='+$blocked) }
}
# The script must return only controlled labels and flags, not sampled JSON.
if ($source -match 'Write-Output\s+\$sample|Write-Output\s+\$xml|Write-Output\s+\$password') {
  throw 'SENSITIVE_OUTPUT'
}
# Synthetic XML fixture: an entity can exist without the other catalogs.
$fixture='<edmx:Edmx xmlns:edmx="urn:example"><edmx:DataServices><Schema><EntityType Name="Catalog_Контрагенты"><Property Name="Ref_Key"/><Property Name="Description"/></EntityType><EntityContainer><EntitySet Name="Catalog_Контрагенты"/></EntityContainer></Schema></edmx:DataServices></edmx:Edmx>'
$settings=New-Object Xml.XmlReaderSettings
$settings.ProhibitDtd=$true
$settings.XmlResolver=$null
$sr=New-Object IO.StringReader -ArgumentList @($fixture)
$xr=[Xml.XmlReader]::Create($sr,$settings)
try {
  $doc=New-Object Xml.XmlDocument
  $doc.XmlResolver=$null
  $doc.Load($xr)
  if ($null -eq $doc.SelectSingleNode("//*[local-name()='EntityType' and @Name='Catalog_Контрагенты']")) { throw 'FIXTURE_CATALOG_NOT_FOUND' }
  if ($null -ne $doc.SelectSingleNode("//*[local-name()='EntityType' and @Name='Catalog_Партнеры']")) { throw 'UNEXPECTED_PARTNER_CATALOG' }
} finally {
  $xr.Close()
  $sr.Close()
}
'COUNTERPARTY_SCHEMA_PS2_PARSE_AND_BOUNDARIES=PASS'
'REAL_NEWBASE_COUNTERPARTY_METADATA=NOT_YET_TESTED'

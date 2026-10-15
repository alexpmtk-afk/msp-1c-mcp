#requires -version 2
# One-shot LocalService-only, GET-only, NewBase metadata validation.
# CLR2 (.NET 2/3.5) compatible: XmlReaderSettings.ProhibitDtd.
# Delivers only status/field-availability to new report; no secret/XML/GUID data.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$state=Join-Path $root 'state'
$report=Join-Path $state 'natural-stock-schema-report-v3.txt'
$secret=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
$base='http://127.0.0.1:8085/NewBase/odata/standard.odata/'
$phase='PRECHECK'
[byte[]]$encrypted=$null
[byte[]]$clear=$null
$credentials=$null
$metadataReader=$null
$textReader=$null
$lines=New-Object 'System.Collections.Generic.List[string]'
[void]$lines.Add('ONEC_NATURAL_STOCK_SCHEMA_V3')
function Record([string]$key,[string]$value) {
  # Only helper-controlled keys and sanitized small values.
  if ($key -notmatch '^[A-Z_]{2,48}$' -or
      $value.Length -gt 100 -or
      $value -notmatch '^[A-Za-z0-9_]+$') { throw 'REPORT_FIELD_INVALID' }
  [void]$script:lines.Add(($key+'='+$value))
}
function Persist {
  if ($script:lines.Count -gt 70) { throw 'REPORT_TOO_MANY_FIELDS' }
  [IO.File]::WriteAllText($script:report,
     ($script:lines -join [Environment]::NewLine),[Text.Encoding]::UTF8)
}
function Flag([bool]$value) { if ($value) { return 'YES' };return 'NO' }
function ReadOnlyOdata([string]$path,[int]$limit) {
  $req=$null;$resp=$null;$reader=$null
  if ($path -match '^(?i)https?:|[\r\n#]' -or
      $path.Length -gt 320) { throw 'INVALID_FIXED_ODATA_PATH' }
  try {
    $req=[Net.HttpWebRequest][Net.WebRequest]::Create($base+$path)
    $req.Method='GET'
    $req.Credentials=$credentials
    $req.PreAuthenticate=$true
    $req.Proxy=$null
    $req.AllowAutoRedirect=$false
    $req.Timeout=45000
    $req.ReadWriteTimeout=15000
    $resp=$req.GetResponse()
    if ([int]$resp.StatusCode -ne 200) { throw 'ODATA_NON_200' }
    $reader=New-Object IO.StreamReader -ArgumentList @($resp.GetResponseStream(),[Text.Encoding]::UTF8)
    $buffer=New-Object char[] 4096
    $sb=New-Object Text.StringBuilder
    $size=0
    do {
      $count=$reader.Read($buffer,0,$buffer.Length)
      $size+=$count
      if ($size -gt $limit) { throw 'ODATA_RESPONSE_TOO_LARGE' }
      if ($count -gt 0) { [void]$sb.Append($buffer,0,$count) }
    } while ($count -gt 0)
    return $sb.ToString()
  } finally {
    if ($null -ne $reader) { $reader.Close() }
    if ($null -ne $resp) { $resp.Close() }
  }
}
function Fields($doc,[string]$entity) {
  $node=$doc.SelectSingleNode("//*[local-name()='EntityType' and @Name='"+$entity+"']")
  if ($null -eq $node) { return @() }
  $result=@()
  foreach($p in $node.SelectNodes("*[local-name()='Property']")) {
    if ($p.GetAttribute('Name')) { $result+=@($p.GetAttribute('Name')) }
  }
  return $result
}
function MatchCount([string]$json) {
  # Only count canonical Ref_Key rows; never return GUIDs.
  if ($json -match '"value"\s*:\s*\[\s*\]') { return 'ZERO' }
  if ($json -notmatch '"value"\s*:\s*\[\s*\{') { throw 'UNEXPECTED_ODATA_JSON' }
  if ($json -match 'odata.nextLink|@odata.nextLink|__next') { throw 'ODATA_PAGINATION_UNVERIFIED' }
  $num=[regex]::Matches($json,'"Ref_Key"\s*:\s*"[0-9a-fA-F-]{36}"').Count
  if ($num -eq 1) { return 'ONE' }
  if ($num -eq 2) { return 'TWO_OR_MORE' }
  throw 'UNEXPECTED_ODATA_JSON'
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_SERVER' }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_PS_VERSION' }
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') { throw 'NOT_LOCAL_SERVICE' }
  if (-not (Test-Path -LiteralPath $state -PathType Container)) { throw 'STATE_DIRECTORY_MISSING' }
  if (Test-Path -LiteralPath $report) { throw 'REPORT_ALREADY_PRESENT' }
  if (-not (Test-Path -LiteralPath $secret -PathType Leaf)) { throw 'READONLY_CREDENTIAL_MISSING' }
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  [byte[]]$encrypted=[IO.File]::ReadAllBytes($secret)
  [byte[]]$clear=[Security.Cryptography.ProtectedData]::Unprotect(
     $encrypted,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $password=[Text.Encoding]::UTF8.GetString($clear)
  if (-not $password -or $password.Length -gt 256) { throw 'INVALID_CREDENTIAL' }
  $credentials=New-Object Net.NetworkCredential -ArgumentList @('MCP_OData_ReadOnly',$password)
  $password=$null

  $phase='METADATA_HTTP_GET'
  $xml=ReadOnlyOdata '$metadata' 16777216
  Record 'METADATA_HTTP_GET' 'PASS'

  $phase='XML_READER_CLR2'
  $settings=New-Object System.Xml.XmlReaderSettings
  # PowerShell 2.0 on CLR2: DtdProcessing was only introduced in CLR4.
  # On both CLR2 and CLR4, ProhibitDtd=$true refuses any DTD.
  $settings.ProhibitDtd=$true
  $settings.XmlResolver=$null
  $settings.MaxCharactersInDocument=16777216
  $textReader=New-Object IO.StringReader -ArgumentList @($xml)
  $metadataReader=[Xml.XmlReader]::Create($textReader,$settings)
  $doc=New-Object Xml.XmlDocument
  $doc.XmlResolver=$null
  $doc.Load($metadataReader)
  Record 'METADATA_XML_PARSE' 'PASS'

  $phase='SCHEMA_PROPERTY_MAP'
  $items=@(Fields $doc 'Catalog_Номенклатура')
  Record 'CATALOG_PRESENT' (Flag ($null -ne $doc.SelectSingleNode("//*[local-name()='EntityType' and @Name='Catalog_Номенклатура']")))
  Record 'CODE_PRESENT' (Flag ($items -ccontains 'Code'))
  Record 'DESCRIPTION_PRESENT' (Flag ($items -ccontains 'Description'))
  Record 'ARTICLE_PRESENT' (Flag ($items -ccontains 'Артикул'))
  $warehouses=@('Catalog_СтруктурныеЕдиницы','Catalog_Склады','Catalog_СкладскиеПомещения','Catalog_СкладыКомпании')
  foreach($entity in $warehouses) {
    $fieldSet=@(Fields $doc $entity)
    if ($fieldSet.Count -gt 0) {
      Record 'WAREHOUSE_ENTITY_PRESENT' ($entity.Replace('Catalog_',''))
      Record 'WAREHOUSE_NAME_PRESENT' (Flag ($fieldSet -ccontains 'Description'))
      Record 'WAREHOUSE_GUID_PRESENT' (Flag ($fieldSet -ccontains 'Ref_Key'))
    }
  }
  $balance=@(Fields $doc 'AccumulationRegister_ЗапасыНаСкладахBalance')
  Record 'BALANCE_ENTITY_PRESENT' (Flag ($balance.Count -gt 0))
  Record 'BALANCE_ITEM_KEY_PRESENT' (Flag ($balance -ccontains 'Номенклатура_Key'))
  Record 'BALANCE_WAREHOUSE_KEY_PRESENT' (Flag ($balance -ccontains 'СтруктурнаяЕдиница_Key'))
  Record 'BALANCE_QUANTITY_PRESENT' (Flag ($balance -ccontains 'КоличествоBalance'))
  Record 'SCHEMA_PROPERTY_MAP' 'PASS'

  $example='трн.02.034.9005.02.30'
  foreach($field in @('Code','Артикул')) {
    $allowed=($items -ccontains $field)
    $result='NOT_PUBLISHED'
    if ($allowed) {
      if ($field -eq 'Code') { $phase='EXACT_CODE_FILTER' } else { $phase='EXACT_ARTICLE_FILTER' }
      $text=$example.Replace("'","''")
      $filter=[Uri]::EscapeDataString(($field+" eq '"+$text+"'"))
      $path='Catalog_Номенклатура?$select=Ref_Key&$filter='+$filter+'&$top=2&$format=json'
      $result=MatchCount (ReadOnlyOdata $path 32768)
    }
    if ($field -eq 'Code') { Record 'EXAMPLE_CODE_MATCHES' $result }
    else { Record 'EXAMPLE_ARTICLE_MATCHES' $result }
  }
  Record 'DATA_WRITES' 'NO'
  Record 'RESULT' 'PASS'
  Persist
  exit 0
} catch {
  $reason='UNCLASSIFIED'
  $errorValue=$_.Exception.Message
  $known=@('WRONG_SERVER','WRONG_PS_VERSION','NOT_LOCAL_SERVICE',
   'STATE_DIRECTORY_MISSING','REPORT_ALREADY_PRESENT',
   'READONLY_CREDENTIAL_MISSING','INVALID_CREDENTIAL',
   'ODATA_RESPONSE_TOO_LARGE','ODATA_NON_200',
   'INVALID_FIXED_ODATA_PATH','ODATA_PAGINATION_UNVERIFIED',
   'UNEXPECTED_ODATA_JSON','REPORT_FIELD_INVALID','REPORT_TOO_MANY_FIELDS')
  if ($known -contains $errorValue) { $reason=$errorValue }
  elseif ($_.Exception -is [Net.WebException]) {
    if ($null -ne $_.Exception.Response) {
      $http=[int]$_.Exception.Response.StatusCode
      try { $_.Exception.Response.Close() } catch {}
      if ($http -eq 401 -or $http -eq 403) { $reason='ODATA_ACCESS_DENIED' }
      elseif ($http -eq 404) { $reason='ODATA_HTTP_NOT_FOUND' }
      else { $reason='ODATA_HTTP_ERROR' }
    } else { $reason='ODATA_NETWORK_ERROR' }
  }
  elseif ($_.Exception -is [Xml.XmlException]) { $reason='INVALID_METADATA_XML' }
  elseif ($_.Exception -is [MissingMemberException] -or
          $_.Exception -is [TypeLoadException]) { $reason='CLR_API_UNAVAILABLE' }
  try {
    Record 'ERROR_PHASE' $phase
    Record 'ERROR_CLASS' $reason
    Record 'RESULT' 'FAIL'
    Persist
  } catch {}
  exit 1
} finally {
  if ($null -ne $metadataReader) { $metadataReader.Close() }
  if ($null -ne $textReader) { $textReader.Close() }
  $credentials=$null
  if ($null -ne $clear) { [Array]::Clear($clear,0,$clear.Length) }
  if ($null -ne $encrypted) { [Array]::Clear($encrypted,0,$encrypted.Length) }
}

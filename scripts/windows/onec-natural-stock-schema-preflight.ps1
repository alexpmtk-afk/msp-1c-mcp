#requires -version 2
# Metadata-only safe NewBase GET probe. No OData credentials, GUIDs, customer
# records or raw response bodies are printed. Requires LocalService (S-1-5-19).
# Not connected to the live SRV scheduler/queue yet.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$secret=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
$base='http://127.0.0.1:8085/NewBase/odata/standard.odata/'
$phase='PRECHECK'
[byte[]]$encrypted=$null
[byte[]]$clear=$null
$credentials=$null
$reader=$null
$metadataReader=$null
function ReadBounded([string]$relative,[int]$limit) {
  $request=$null
  $response=$null
  $stream=$null
  $bodyReader=$null
  try {
    if ($relative -match '(?i)^https?:|[\r\n#]') { throw 'UNSAFE_PATH' }
    $request=[Net.HttpWebRequest][Net.WebRequest]::Create($base+$relative)
    $request.Method='GET'
    $request.Credentials=$credentials
    $request.PreAuthenticate=$true
    $request.Proxy=$null
    $request.AllowAutoRedirect=$false
    $request.Timeout=45000
    $request.ReadWriteTimeout=12000
    $response=$request.GetResponse()
    if ([int]$response.StatusCode -ne 200) { throw 'NON_200' }
    $stream=$response.GetResponseStream()
    $bodyReader=New-Object IO.StreamReader -ArgumentList @($stream,[Text.Encoding]::UTF8)
    $chars=New-Object char[] 4096
    $sb=New-Object Text.StringBuilder
    $count=0
    do {
      $n=$bodyReader.Read($chars,0,$chars.Length)
      $count+=$n
      if ($count -gt $limit) { throw 'RESPONSE_TOO_LARGE' }
      if ($n -gt 0) { [void]$sb.Append($chars,0,$n) }
    } while ($n -gt 0)
    return $sb.ToString()
  } finally {
    if ($null -ne $bodyReader) { $bodyReader.Close() }
    if ($null -ne $response) { $response.Close() }
  }
}
function PropertyNames($doc,[string]$entity) {
  $node=$doc.SelectSingleNode("//*[local-name()='EntityType' and @Name='"+$entity+"']")
  if ($null -eq $node) { return @() }
  $result=@()
  foreach($prop in $node.SelectNodes("*[local-name()='Property']")) {
    $name=$prop.GetAttribute('Name')
    if ($name) { $result+=@($name) }
  }
  return $result
}
function Flag([bool]$b) { if($b){return 'YES'}else{return 'NO'} }
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_SERVER' }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_PS_VERSION' }
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') {
    throw 'WRONG_IDENTITY'
  }
  if (-not (Test-Path -LiteralPath $secret -PathType Leaf)) { throw 'NO_CREDENTIAL' }
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  [byte[]]$encrypted=[IO.File]::ReadAllBytes($secret)
  [byte[]]$clear=[Security.Cryptography.ProtectedData]::Unprotect(
      $encrypted,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $password=[Text.Encoding]::UTF8.GetString($clear)
  if (-not $password -or $password.Length -gt 256) { throw 'INVALID_CREDENTIAL' }
  $credentials=New-Object Net.NetworkCredential -ArgumentList @('MCP_OData_ReadOnly',$password)
  $password=$null
  $phase='SCHEMA_GET'
  $xml=ReadBounded '$metadata' 16777216
  $settings=New-Object Xml.XmlReaderSettings
  $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver=$null
  $settings.MaxCharactersInDocument=16777216
  $reader=New-Object IO.StringReader -ArgumentList @($xml)
  $metadataReader=[Xml.XmlReader]::Create($reader,$settings)
  $doc=New-Object Xml.XmlDocument
  $doc.XmlResolver=$null
  $doc.Load($metadataReader)
  $items=@(PropertyNames $doc 'Catalog_Номенклатура')
  $itemEntity=($null -ne $doc.SelectSingleNode("//*[local-name()='EntityType' and @Name='Catalog_Номенклатура']"))
  $articlePresent=($items -ccontains 'Артикул')
  $articleFields=@($items | Where-Object { $_ -match 'Артикул' })
  if ($articleFields.Count -gt 10) { throw 'TOO_MANY_ARTICLE_FIELDS' }
  $nameField=if($items -ccontains 'Description'){'Description'}elseif($items -ccontains 'Наименование'){'Наименование'}else{'NOT_VERIFIED'}
  $codePresent=($items -ccontains 'Code')
  $warehouseCandidates=@('Catalog_СтруктурныеЕдиницы','Catalog_Склады','Catalog_СкладскиеПомещения','Catalog_СкладыКомпании')
  $warehouseFields=@{}
  $warehouseNames=@()
  foreach($candidate in $warehouseCandidates) {
    $node=$doc.SelectSingleNode("//*[local-name()='EntityType' and @Name='"+$candidate+"']")
    if ($null -ne $node) {
      $warehouseNames+=@($candidate)
      $warehouseFields[$candidate]=@(PropertyNames $doc $candidate)
    }
  }
  $balance=$doc.SelectSingleNode("//*[local-name()='EntityType' and @Name='AccumulationRegister_ЗапасыНаСкладахBalance']")
  $balanceProperties=@(PropertyNames $doc 'AccumulationRegister_ЗапасыНаСкладахBalance')
  $phase='EXACT_ARTICLE_FILTER'
  # Probe different fields separately. Code is the internal 1C catalog code;
  # it is not presumed equal to a customer-facing article.
  $article='трн.02.034.9005.02.30'
  $codeMatches='NOT_TESTED'
  $articleMatches='NOT_TESTED'
  $lookupFields=@()
  if ($codePresent) { $lookupFields+=@('Code') }
  if ($articlePresent) { $lookupFields+=@('Артикул') }
  foreach($field in $lookupFields) {
    $escaped=$article.Replace("'","''")
    $filter=[Uri]::EscapeDataString(($field+" eq '"+$escaped+"'"))
    $path='Catalog_Номенклатура?$select=Ref_Key&$filter='+$filter+'&$top=2&$format=json'
    $json=ReadBounded $path 32768
    $found='INVALID'
    if ($json -match '"value"\s*:\s*\[\s*\]') { $found='ZERO' }
    elseif ($json -match '"value"\s*:\s*\[\s*\{') {
      $keys=[regex]::Matches($json,'"Ref_Key"\s*:\s*"[0-9a-fA-F-]{36}"')
      if ($keys.Count -eq 1) { $found='ONE' }
      elseif ($keys.Count -eq 2) { $found='TWO_OR_MORE' }
    }
    if ($found -eq 'INVALID') { throw 'INVALID_LOOKUP_RESPONSE' }
    if ($field -eq 'Code') { $codeMatches=$found }
    if ($field -eq 'Артикул') { $articleMatches=$found }
  }
  Write-Output 'ONEC_NATURAL_STOCK_SCHEMA_PREFLIGHT'
  Write-Output 'ODATA_METADATA_GET=PASS'
  Write-Output ('ITEM_CATALOG_PRESENT='+(Flag $itemEntity))
  Write-Output ('ARTICLE_FIELD_PRESENT='+(Flag $articlePresent))
  Write-Output ('ARTICLE_FIELD_CANDIDATE_COUNT='+$articleFields.Count)
  foreach($field in $articleFields) { Write-Output ('ARTICLE_FIELD_CANDIDATE='+$field) }
  Write-Output ('NAME_FIELD='+$nameField)
  Write-Output ('CODE_FIELD_PRESENT='+(Flag $codePresent))
  Write-Output ('WAREHOUSE_ENTITY_CANDIDATE_COUNT='+$warehouseNames.Count)
  foreach($name in $warehouseNames) {
    Write-Output ('WAREHOUSE_ENTITY='+$name)
    Write-Output ('WAREHOUSE_HAS_REF_KEY='+(Flag ($warehouseFields[$name] -ccontains 'Ref_Key')))
    Write-Output ('WAREHOUSE_HAS_DESCRIPTION='+(Flag ($warehouseFields[$name] -ccontains 'Description')))
  }
  Write-Output ('BALANCE_ENTITY_PRESENT='+(Flag ($null -ne $balance)))
  Write-Output ('BALANCE_ITEM_KEY_PRESENT='+(Flag ($balanceProperties -ccontains 'Номенклатура_Key')))
  Write-Output ('BALANCE_WAREHOUSE_KEY_PRESENT='+(Flag ($balanceProperties -ccontains 'СтруктурнаяЕдиница_Key')))
  Write-Output ('BALANCE_QUANTITY_PRESENT='+(Flag ($balanceProperties -ccontains 'КоличествоBalance')))
  Write-Output ('EXAMPLE_ARTICLE_MATCHES='+$articleMatches)
  Write-Output ('EXAMPLE_CODE_MATCHES='+$codeMatches)
  Write-Output 'RAW_NOMENCLATURE_AND_GUIDS_EXPORTED=NO'
  Write-Output 'RAW_CUSTOMERS_OR_CREDENTIALS_EXPORTED=NO'
  Write-Output 'ODATA_GET_ONLY=YES'
  Write-Output 'DATA_WRITES=NO'
  Write-Output 'RESULT=PASS'
  exit 0
} catch {
  Write-Output 'ONEC_NATURAL_STOCK_SCHEMA_PREFLIGHT'
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';DETAILS=REDACTED')
  exit 1
} finally {
  if ($null -ne $metadataReader) { $metadataReader.Close() }
  if ($null -ne $reader) { $reader.Close() }
  $credentials=$null
  if ($null -ne $clear) { [Array]::Clear($clear,0,$clear.Length) }
  if ($null -ne $encrypted) { [Array]::Clear($encrypted,0,$encrypted.Length) }
}

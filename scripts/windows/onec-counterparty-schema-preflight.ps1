#requires -version 2
# Read-only schema and field-presence verification for 1C NewBase counterparty candidates.
# No raw data, names, addresses, contact details, tax IDs, GUIDs or credentials leave SRV.
# Manual, approved LocalService invocation only. No scheduler or queue changes.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$secret=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
$base='http://127.0.0.1:8085/NewBase/odata/standard.odata/'
[byte[]]$encrypted=$null
[byte[]]$clear=$null
$credentials=$null
$xmlReader=$null
$textReader=$null
$phase='PREFLIGHT'
function BoundedGet([string]$path,[int]$limit) {
  $request=$null;$response=$null;$streamReader=$null
  if ($path.Length -gt 256 -or $path -match '^(?i)https?:|[\r\n#]') { throw 'INVALID_FIXED_PATH' }
  try {
    $request=[Net.HttpWebRequest][Net.WebRequest]::Create($base+$path)
    $request.Method='GET'
    $request.Credentials=$credentials
    $request.PreAuthenticate=$true
    $request.Proxy=$null
    $request.AllowAutoRedirect=$false
    $request.Timeout=30000
    $request.ReadWriteTimeout=15000
    $response=$request.GetResponse()
    if ([int]$response.StatusCode -ne 200) { throw 'ODATA_NON_200' }
    $streamReader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
    $builder=New-Object Text.StringBuilder
    $buffer=New-Object char[] 4096
    $count=0
    do {
      $read=$streamReader.Read($buffer,0,$buffer.Length)
      $count+=$read
      if ($count -gt $limit) { throw 'RESPONSE_TOO_LARGE' }
      if ($read -gt 0) { [void]$builder.Append($buffer,0,$read) }
    } while ($read -gt 0)
    return $builder.ToString()
  } finally {
    if ($null -ne $streamReader) { $streamReader.Close() }
    if ($null -ne $response) { $response.Close() }
  }
}
function Flag([bool]$value) { if($value){return 'YES'};return 'NO' }
function SchemaProperties($node) {
  $names=@()
  if ($null -eq $node) { return $names }
  foreach($p in $node.SelectNodes("*[local-name()='Property']")) {
    $name=$p.GetAttribute('Name')
    if ($name) { $names+=@($name) }
  }
  return $names
}
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { throw 'WRONG_SERVER' }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_POWERSHELL' }
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') { throw 'WRONG_IDENTITY' }
  if (-not (Test-Path -LiteralPath $secret -PathType Leaf)) { throw 'CREDENTIAL_UNAVAILABLE' }
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  [byte[]]$encrypted=[IO.File]::ReadAllBytes($secret)
  [byte[]]$clear=[Security.Cryptography.ProtectedData]::Unprotect(
    $encrypted,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $password=[Text.Encoding]::UTF8.GetString($clear)
  if (-not $password -or $password.Length -gt 256) { throw 'CREDENTIAL_INVALID' }
  $credentials=New-Object Net.NetworkCredential -ArgumentList @('MCP_OData_ReadOnly',$password)
  $password=$null
  $phase='METADATA_GET'
  $xml=BoundedGet '$metadata' 16777216
  $phase='METADATA_PARSE'
  $settings=New-Object Xml.XmlReaderSettings
  $settings.ProhibitDtd=$true
  $settings.XmlResolver=$null
  $settings.MaxCharactersInDocument=16777216
  $textReader=New-Object IO.StringReader -ArgumentList @($xml)
  $xmlReader=[Xml.XmlReader]::Create($textReader,$settings)
  $document=New-Object Xml.XmlDocument
  $document.XmlResolver=$null
  $document.Load($xmlReader)
  $xml=$null
  Write-Output 'ONEC_COUNTERPARTY_SCHEMA_PREFLIGHT'
  Write-Output 'METADATA_READ=PASS'
  $candidates=@(
    @('COUNTERPARTIES','Catalog_Контрагенты'),
    @('PARTNERS','Catalog_Партнеры'),
    @('ORGANIZATIONS','Catalog_Организации')
  )
  foreach($candidate in $candidates) {
    [string]$label=$candidate[0]
    [string]$entityName=$candidate[1]
    $node=$document.SelectSingleNode("//*[local-name()='EntityType' and @Name='"+$entityName+"']")
    $set=$document.SelectSingleNode("//*[local-name()='EntitySet' and @Name='"+$entityName+"']")
    $present=($null -ne $node -and $null -ne $set)
    $fields=@(SchemaProperties $node)
    Write-Output ($label+'_PUBLISHED='+(Flag $present))
    if (-not $present) { continue }
    foreach($field in @('Ref_Key','Description','Code','DeletionMark','Parent_Key','ИНН','КПП','НаименованиеПолное')) {
      $token=if($field -eq 'Ref_Key'){'REF_KEY'}elseif($field -eq 'Description'){'DESCRIPTION'}elseif($field -eq 'Code'){'CODE'}elseif($field -eq 'DeletionMark'){'DELETION_MARK'}elseif($field -eq 'Parent_Key'){'PARENT_KEY'}elseif($field -eq 'ИНН'){'TAX_ID'}elseif($field -eq 'КПП'){'TAX_BRANCH'}else{'FULL_NAME'}
      Write-Output ($label+'_'+$token+'_FIELD='+(Flag ($fields -ccontains $field)))
    }
    if ($fields -ccontains 'Ref_Key') {
      # Exactly one bounded GET to check authorization, never publish its body.
      $phase='CATALOG_SAMPLE_GET'
      try {
        $sample=BoundedGet ($entityName+'?$select=Ref_Key&$top=1&$format=json') 32768
        if ($sample -match '"value"\s*:\s*\[') { $readStatus='PASS' }
        else { $readStatus='UNEXPECTED_RESPONSE' }
        $sample=$null
      } catch { $readStatus='UNAVAILABLE' }
      Write-Output ($label+'_READ_ACCESS='+$readStatus)
    } else {
      Write-Output ($label+'_READ_ACCESS=FIELD_MISSING')
    }
  }
  Write-Output 'RECORD_DATA_EXPORTED=NO'
  Write-Output 'CREDENTIALS_EXPORTED=NO'
  Write-Output 'ODATA_GET_ONLY=YES'
  Write-Output 'NEW_MCP_ENABLED=NO'
  Write-Output 'RESULT=PASS'
  exit 0
} catch {
  Write-Output 'ONEC_COUNTERPARTY_SCHEMA_PREFLIGHT'
  Write-Output ('RESULT=FAIL;PHASE='+$phase+';DETAILS=REDACTED')
  exit 1
} finally {
  if ($null -ne $xmlReader) { $xmlReader.Close() }
  if ($null -ne $textReader) { $textReader.Close() }
  $credentials=$null
  if ($null -ne $clear) { [Array]::Clear($clear,0,$clear.Length) }
  if ($null -ne $encrypted) { [Array]::Clear($encrypted,0,$encrypted.Length) }
}

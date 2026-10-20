#requires -version 2
# Native PS2; ASCII-only script source. Read ONLY OData $metadata from test 1C.
# Never fetch customer rows or send data outside SRV.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
$response=$null
$phase='PRECHECK'
function Fail([string]$Code) {throw ('ODATA_'+$Code)}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($null -eq $Credential){
    $secure=Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString
    if($null -eq $secure -or $secure.Length -eq 0){throw 'PASSWORD_REQUIRED'}
    $Credential=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
    $secure=$null
  }
  if($Credential.UserName -ne 'MCP_OData_ReadOnly'){throw 'ODATA_USERNAME_MISMATCH'}
  if($null -eq $Credential){Fail 'CREDENTIAL_REQUIRED'}
  $phase='ODATA_METADATA_GET'
  $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/$metadata'
  $request=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $request.Method='GET'
  $request.Proxy=$null
  $request.AllowAutoRedirect=$false
  $request.Credentials=$Credential.GetNetworkCredential()
  $request.PreAuthenticate=$true
  $request.Timeout=15000
  $request.ReadWriteTimeout=15000
  $response=$request.GetResponse()
  if([int]$response.StatusCode -ne 200){Fail 'HTTP_NOT_200'}
  $phase='LIMITED_XML_READ'
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
  try {
    $buf=New-Object char[] 8192
    $sb=New-Object Text.StringBuilder
    $characters=0
    do {
      $n=$reader.Read($buf,0,$buf.Length)
      $characters+=$n
      if($characters -gt 16777216){Fail 'METADATA_TOO_LARGE'}
      if($n -gt 0){[void]$sb.Append($buf,0,$n)}
    } while($n -gt 0)
  } finally {$reader.Close()}
  $phase='PARSE_METADATA'
  $xml=New-Object Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.LoadXml($sb.ToString())
  $sets=@($xml.SelectNodes("//*[local-name()='EntitySet']"))
  $types=@($xml.SelectNodes("//*[local-name()='EntityType']"))
  $targets=@(
    @{Role='COUNTERPARTIES';Pattern='^Catalog_\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b$'},
    @{Role='COUNTERPARTY_CONTACT_INFO';Pattern='^Catalog_\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b_\u041a\u043e\u043d\u0442\u0430\u043a\u0442\u043d\u0430\u044f\u0418\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f$'}
  )
  'HTTP=200'
  'ENTITY_SETS='+$sets.Count
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'DATA_WRITES=NO'
  foreach($target in $targets){
    $matched=@($sets | Where-Object {$_.GetAttribute('Name') -match $target.Pattern})
    if($matched.Count -ne 1){'ROLE='+$target.Role+';ENTITY_SET_MATCHES='+$matched.Count;continue}
    $set=$matched[0]
    $typeName=$set.GetAttribute('EntityType')
    $leaf=$typeName.Substring($typeName.LastIndexOf('.')+1)
    $matches=@($types | Where-Object {$_.GetAttribute('Name') -eq $leaf})
    'ROLE='+$target.Role
    'ENTITY_SET='+$set.GetAttribute('Name')
    'ENTITY_TYPE='+$typeName
    if($matches.Count -ne 1){'ENTITY_TYPE_MATCHES='+$matches.Count;continue}
    $etype=$matches[0]
    $keys=@($etype.SelectNodes("./*[local-name()='Key']/*[local-name()='PropertyRef']"))
    'KEY_COUNT='+$keys.Count
    foreach($key in $keys){'KEY='+$key.GetAttribute('Name')}
    $properties=@($etype.SelectNodes("./*[local-name()='Property']"))
    'PROPERTY_COUNT='+$properties.Count
    $limit=[Math]::Min(140,$properties.Count)
    for($i=0;$i -lt $limit;$i++){
      $property=$properties[$i]
      'FIELD='+$property.GetAttribute('Name')+';TYPE='+$property.GetAttribute('Type')
    }
    'FIELDS_TRUNCATED='+($properties.Count -gt $limit)
  }
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'RESULT=PASS;STAGE=BITRIX24_CUSTOMER_SCHEMA'
}catch [Net.WebException]{
  $code='TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){
    $code='HTTP_'+[int]$_.Exception.Response.StatusCode
  }
  'RESULT=FAIL;STAGE=BITRIX24_CUSTOMER_SCHEMA;GATE='+$code
}catch{
  $message=$_.Exception.Message
  $code='SCHEMA_ERROR'
  if($message -match '^ODATA_([A-Z_]+)$'){$code=$Matches[1]}
  'RESULT=FAIL;STAGE=BITRIX24_CUSTOMER_SCHEMA;GATE='+$code
  'FAILURE_PHASE='+$phase
}finally{
  if($null -ne $response){$response.Close()}
}

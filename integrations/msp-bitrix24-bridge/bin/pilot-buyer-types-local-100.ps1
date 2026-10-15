#requires -version 2
# Native PS2 read-only SAMPLE: enum categories only, not individual customers.
# Test 1C localhost OData only. Never export names, GUIDs, INNs or rows.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$response=$null
function Fail([string]$Reason){throw ('ODATA_'+$Reason)}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($null -eq $Credential){
    $secure=Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString
    if($null -eq $secure -or $secure.Length -eq 0){Fail 'PASSWORD_REQUIRED'}
    $Credential=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
    $secure=$null
  }
  if($Credential.UserName -ne 'MCP_OData_ReadOnly'){Fail 'USERNAME_MISMATCH'}
  $name=[regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')
  $typeName=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u0424\u0438\u0437\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
  $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
  $filter=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
  $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$name+
    '?$filter='+[Uri]::EscapeDataString($filter)+
    '&$select='+[Uri]::EscapeDataString('Ref_Key,'+$typeName)+
    '&$orderby=Ref_Key%20asc&$top=100'
  $phase='REQUEST'
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET'
  $req.Accept='application/atom+xml'
  $req.Proxy=$null
  $req.AllowAutoRedirect=$false
  $req.Credentials=$Credential.GetNetworkCredential()
  $req.PreAuthenticate=$true
  $req.Timeout=15000
  $req.ReadWriteTimeout=15000
  $response=$req.GetResponse()
  if([int]$response.StatusCode -ne 200){Fail 'HTTP_NOT_200'}
  $phase='BOUNDED_XML_READ'
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
  try {
    $buf=New-Object char[] 8192
    $sb=New-Object Text.StringBuilder
    $size=0
    do {
      $n=$reader.Read($buf,0,$buf.Length)
      $size+=$n
      if($size -gt 1048576){Fail 'RESPONSE_TOO_LARGE'}
      if($n -gt 0){[void]$sb.Append($buf,0,$n)}
    } while($n -gt 0)
  }finally{$reader.Close()}
  $phase='CLASSIFY_100'
  $xml=New-Object Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.LoadXml($sb.ToString())
  if($xml.DocumentElement.LocalName -ne 'feed'){Fail 'NOT_ATOM_FEED'}
  $rows=@($xml.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']"))
  if($rows.Count -lt 1 -or $rows.Count -gt 100){Fail 'SAMPLE_ROW_COUNT_INVALID'}
  $seen=@{}
  $groups=@{}
  foreach($entry in $rows){
    $props=$entry.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
    if($null -eq $props){Fail 'PROPERTIES_MISSING'}
    $id=$props.SelectSingleNode("./*[local-name()='Ref_Key']")
    $kind=$props.SelectSingleNode("./*[local-name()='"+$typeName+"']")
    if($null -eq $id -or $null -eq $kind){Fail 'SELECTED_FIELDS_MISSING'}
    $guid=$id.InnerText.Trim().ToLowerInvariant()
    if($guid -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){Fail 'INVALID_GUID'}
    if($seen.ContainsKey($guid)){Fail 'DUPLICATE_GUID'}
    $seen[$guid]=$true
    $category=$kind.InnerText.Trim()
    if($category -eq ''){$category='EMPTY'}
    if($category -notmatch '^[\p{L}\p{N}_ .-]{1,128}$'){$category='UNSAFE_OR_LONG'}
    if(-not $groups.ContainsKey($category)){$groups[$category]=0}
    $groups[$category]++
  }
  if($seen.Count -ne $rows.Count){Fail 'SAMPLE_UNIQUENESS_MISMATCH'}
  'HTTP=200'
  'SAMPLE_ONLY=YES'
  'SAMPLE_ROWS='+$rows.Count
  'SAMPLE_UNIQUE_GUIDS='+$seen.Count
  'CATEGORY_COUNT='+$groups.Count
  foreach($label in @($groups.Keys | Sort-Object)){
    'CATEGORY='+$label+';COUNT='+$groups[$label]
  }
  'POPULATION_CLASSIFICATION=NOT_YET'
  'CUSTOMER_ROWS_PROCESSED_LOCALLY=YES'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'RAW_IDENTIFIERS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=BITRIX24_BUYER_TYPE_SAMPLE'
}catch [Net.WebException]{
  $gate='TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  'RESULT=FAIL;STAGE=BITRIX24_BUYER_TYPE_SAMPLE;GATE='+$gate
  'FAILURE_PHASE='+$phase
}catch{
  $msg=$_.Exception.Message
  $gate='LOCAL_RUNTIME_ERROR'
  if($msg -match '^ODATA_([A-Z_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=BITRIX24_BUYER_TYPE_SAMPLE;GATE='+$gate
  'FAILURE_PHASE='+$phase
}finally {
  if($null -ne $response){$response.Close()}
}

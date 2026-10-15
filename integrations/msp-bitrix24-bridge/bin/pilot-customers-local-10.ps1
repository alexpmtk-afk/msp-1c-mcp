#requires -version 2
# Safe read-only ten-row LOCAL pilot for unlimited-length name fields in 1C TEST OData.
# Native PowerShell 2 ASCII source. No personal data, identifiers, URLs or body in output.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$response=$null
function Fail([string]$Code){throw ('ODATA_'+$Code)}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($null -eq $Credential){
    $secure=Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString
    if($null -eq $secure -or $secure.Length -eq 0){Fail 'PASSWORD_REQUIRED'}
    $Credential=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
    $secure=$null
  }
  if($Credential.UserName -ne 'MCP_OData_ReadOnly'){Fail 'USERNAME_MISMATCH'}
  $name=[regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')
  $full=[regex]::Unescape('\u041d\u0430\u0438\u043c\u0435\u043d\u043e\u0432\u0430\u043d\u0438\u0435\u041f\u043e\u043b\u043d\u043e\u0435')
  $inn=[regex]::Unescape('\u0418\u041d\u041d')
  $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
  $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
  $filter=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
  $base='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$name
  $url=$base+'?$filter='+[Uri]::EscapeDataString($filter)+
    '&$select='+[Uri]::EscapeDataString('Ref_Key,'+$full+','+$inn)+
    '&$orderby=Ref_Key%20asc&$top=10'
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
  $phase='BOUNDED_READ'
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
  try{
    $buf=New-Object char[] 8192
    $text=New-Object Text.StringBuilder
    $size=0
    do {
      $n=$reader.Read($buf,0,$buf.Length)
      $size+=$n
      if($size -gt 1048576){Fail 'RESPONSE_TOO_LARGE'}
      if($n -gt 0){[void]$text.Append($buf,0,$n)}
    } while($n -gt 0)
  }finally{$reader.Close()}
  $phase='LOCAL_XML_PARSING'
  $xml=New-Object Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.LoadXml($text.ToString())
  if($xml.DocumentElement.LocalName -ne 'feed'){Fail 'NOT_ATOM_FEED'}
  $items=@($xml.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']"))
  if($items.Count -lt 1 -or $items.Count -gt 10){Fail 'UNEXPECTED_ROW_COUNT'}
  $fullCount=0
  $innCount=0
  $bothCount=0
  foreach($item in $items){
    $props=$item.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
    if($null -eq $props){Fail 'PROPERTIES_MISSING'}
    $id=$props.SelectSingleNode("./*[local-name()='Ref_Key']")
    $fullNode=$props.SelectSingleNode("./*[local-name()='"+$full+"']")
    $innNode=$props.SelectSingleNode("./*[local-name()='"+$inn+"']")
    if($null -eq $id -or $null -eq $fullNode -or $null -eq $innNode){Fail 'SELECTED_FIELDS_MISSING'}
    if($id.InnerText -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'){Fail 'GUID_INVALID'}
    $hasFull=($fullNode.InnerText.Trim().Length -gt 0)
    $hasInn=($innNode.InnerText.Trim().Length -gt 0)
    if($hasFull){$fullCount++}
    if($hasInn){$innCount++}
    if($hasFull -and $hasInn){$bothCount++}
  }
  'HTTP=200'
  'PILOT_ONLY=YES'
  'PILOT_ROWS='+$items.Count
  'PILOT_FULL_NAME_NONBLANK='+$fullCount
  'PILOT_INN_NONBLANK='+$innCount
  'PILOT_BOTH_NONBLANK='+$bothCount
  'COMPLETE_CUSTOMER_COUNTS=NOT_YET'
  'CUSTOMER_ROWS_PROCESSED_LOCALLY=YES'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'RAW_IDENTIFIERS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=BITRIX24_LOCAL_10_ROW_PILOT'
}catch [Net.WebException]{
  $gate='TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  'RESULT=FAIL;STAGE=BITRIX24_LOCAL_10_ROW_PILOT;GATE='+$gate
  'FAILURE_PHASE='+$phase
}catch{
  $msg=$_.Exception.Message
  $gate='LOCAL_RUNTIME_ERROR'
  if($msg -match '^ODATA_([A-Z_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=BITRIX24_LOCAL_10_ROW_PILOT;GATE='+$gate
  'FAILURE_PHASE='+$phase
}finally{
  if($null -ne $response){$response.Close()}
}

#requires -version 2
# Manual sandbox OData metadata inventory only. No customer rows leave SRV.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
function Fail([string]$Reason) {
  Write-Output ('RESULT=FAIL;STAGE=BITRIX24_ODATA_INVENTORY;GATE='+$Reason)
  exit 1
}
$response=$null
try {
  if ($env:COMPUTERNAME -ne $ExpectedComputerName) { Fail 'WRONG_HOST' }
  if ($null -eq $Credential) { Fail 'CREDENTIAL_REQUIRED' }
  $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/$metadata'
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET'
  $req.Credentials=$Credential.GetNetworkCredential()
  $req.PreAuthenticate=$true
  $req.Proxy=$null
  $req.AllowAutoRedirect=$false
  $req.Timeout=15000
  $req.ReadWriteTimeout=15000
  $response=$req.GetResponse()
  if ([int]$response.StatusCode -ne 200) { Fail 'HTTP_NOT_200' }
  $stream=$response.GetResponseStream()
  $reader=New-Object IO.StreamReader -ArgumentList @($stream,[Text.Encoding]::UTF8)
  try {
    $buffer=New-Object char[] 8192
    $count=0
    $text=New-Object Text.StringBuilder
    do {
      $n=$reader.Read($buffer,0,$buffer.Length)
      $count+=$n
      if ($count -gt 16777216) { Fail 'METADATA_TOO_LARGE' }
      if ($n -gt 0) { [void]$text.Append($buffer,0,$n) }
    } while ($n -gt 0)
  } finally { $reader.Close() }
  $xml=New-Object Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.LoadXml($text.ToString())
  $names=@($xml.SelectNodes("//*[local-name()='EntitySet']") | ForEach-Object { $_.GetAttribute('Name') })
  $candidates=@($names | Where-Object { $_ -match '^Catalog_.*(Контраген|Партнер|Покупател|Клиент)' })
  'HTTP=200'
  'ENTITY_SETS='+$names.Count
  'CUSTOMER_CANDIDATES='+$candidates.Count
  foreach($x in $candidates | Sort-Object -Unique | Select-Object -First 25) { 'CANDIDATE='+$x }
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'RESULT=PASS;STAGE=BITRIX24_ODATA_INVENTORY'
} catch [Net.WebException] {
  if ($_.Exception.Response) {
    'RESULT=FAIL;STAGE=BITRIX24_ODATA_INVENTORY;HTTP='+[int]$_.Exception.Response.StatusCode
  } else { Fail 'TRANSPORT_ERROR' }
} catch {
  Fail 'METADATA_READ_ERROR'
} finally {
  if ($null -ne $response) { $response.Close() }
}

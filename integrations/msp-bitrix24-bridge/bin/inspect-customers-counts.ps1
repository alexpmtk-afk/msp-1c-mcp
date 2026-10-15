#requires -version 2
# Read-only aggregate counts in the isolated 1C NewBase OData TEST database.
# Endpoints return only integer counts, never customer records or identifiers.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
$response=$null
function Fail([string]$Code){throw ('ODATA_'+$Code)}
function ReadCount([string]$Filter){
  $response=$null
  $reader=$null
  try{
    $base='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+
      [regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')+'/$count'
    $uri=$base
    if($Filter -ne ''){$uri+='?$filter='+[Uri]::EscapeDataString($Filter)}
    $request=[Net.HttpWebRequest][Net.WebRequest]::Create($uri)
    $request.Method='GET'
    $request.Proxy=$null
    $request.AllowAutoRedirect=$false
    $request.Credentials=$Credential.GetNetworkCredential()
    $request.PreAuthenticate=$true
    $request.Timeout=15000
    $request.ReadWriteTimeout=15000
    $response=$request.GetResponse()
    if([int]$response.StatusCode -ne 200){Fail 'COUNT_HTTP_NOT_200'}
    $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::ASCII)
    $raw=$reader.ReadToEnd().Trim()
    if($raw -notmatch '^[0-9]{1,12}$'){Fail 'COUNT_NON_NUMERIC_RESPONSE'}
    $number=[long]0
    if(-not [long]::TryParse($raw,[ref]$number)){Fail 'COUNT_PARSE_FAILED'}
    return $number
  } finally {
    if($null -ne $reader){$reader.Close()}
    if($null -ne $response){$response.Close()}
  }
}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($null -eq $Credential){$Credential=Get-Credential}
  if($null -eq $Credential){Fail 'CREDENTIAL_REQUIRED'}
  $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
  $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
  $countAll=ReadCount ''
  $countBuyers=ReadCount ($buyer+' eq true')
  $countEligible=ReadCount ($buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false')
  if($countEligible -gt $countBuyers -or $countBuyers -gt $countAll){Fail 'COUNTS_INCONSISTENT'}
  'COUNTERPARTIES_TOTAL='+$countAll
  'BUYER_FLAG_TRUE='+$countBuyers
  'BUYER_ACTIVE_NOT_DELETED='+$countEligible
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'RAW_IDENTIFIERS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=BITRIX24_CUSTOMER_COUNTS'
}catch [Net.WebException] {
  $errorCode='COUNT_TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){
    $errorCode='HTTP_'+[int]$_.Exception.Response.StatusCode
  }
  'RESULT=FAIL;STAGE=BITRIX24_CUSTOMER_COUNTS;GATE='+$errorCode
}catch{
  $message=$_.Exception.Message
  $gate='COUNT_RUNTIME_ERROR'
  if($message -match '^ODATA_([A-Z_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=BITRIX24_CUSTOMER_COUNTS;GATE='+$gate
}

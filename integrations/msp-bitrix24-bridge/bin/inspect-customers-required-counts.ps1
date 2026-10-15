#requires -version 2
# Read-only 1C TEST OData integer counts for mandatory organization fields.
# ASCII-only source for legacy Windows PowerShell 2. No rows or IDs returned.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
function Fail([string]$Code){throw ('ODATA_'+$Code)}
function CountRows([string]$Filter){
  $response=$null
  $reader=$null
  try{
    $base='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+
      [regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')+'/$count'
    $uri=$base+'?$filter='+[Uri]::EscapeDataString($Filter)
    $req=[Net.HttpWebRequest][Net.WebRequest]::Create($uri)
    $req.Method='GET'
    $req.Credentials=$Credential.GetNetworkCredential()
    $req.PreAuthenticate=$true
    $req.Proxy=$null
    $req.AllowAutoRedirect=$false
    $req.Timeout=15000
    $req.ReadWriteTimeout=15000
    $response=$req.GetResponse()
    if([int]$response.StatusCode -ne 200){Fail 'HTTP_NOT_200'}
    $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::ASCII)
    $raw=$reader.ReadToEnd().Trim()
    if($raw -notmatch '^[0-9]{1,12}$'){Fail 'NON_NUMERIC_COUNT'}
    $count=[long]0
    if(-not [long]::TryParse($raw,[ref]$count)){Fail 'COUNT_PARSE_FAILED'}
    return $count
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
  $full=[regex]::Unescape('\u041d\u0430\u0438\u043c\u0435\u043d\u043e\u0432\u0430\u043d\u0438\u0435\u041f\u043e\u043b\u043d\u043e\u0435')
  $inn=[regex]::Unescape('\u0418\u041d\u041d')
  $base=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
  $countEligible=CountRows $base
  $countFull=CountRows ($base+' and '+$full+" ne ''")
  $countInn=CountRows ($base+' and '+$inn+" ne ''")
  $countBoth=CountRows ($base+' and '+$full+" ne '' and "+$inn+" ne ''")
  if($countBoth -gt $countFull -or $countBoth -gt $countInn -or
    $countFull -gt $countEligible -or $countInn -gt $countEligible){Fail 'COUNTS_INCONSISTENT'}
  'BUYER_ACTIVE_NOT_DELETED='+$countEligible
  'FULL_NAME_NONEMPTY='+$countFull
  'INN_NONEMPTY='+$countInn
  'BOTH_FIELDS_NONEMPTY='+$countBoth
  'FULL_NAME_EMPTY_OR_NOT_MATCHED='+($countEligible-$countFull)
  'INN_EMPTY_OR_NOT_MATCHED='+($countEligible-$countInn)
  'EITHER_FIELD_EMPTY_OR_NOT_MATCHED='+($countEligible-$countBoth)
  'ALL_CUSTOMER_TYPES_INCLUDED=YES'
  'WHITESPACE_ONLY_NOT_VALIDATED=YES'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'RAW_IDENTIFIERS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=BITRIX24_REQUIRED_FIELD_COUNTS'
} catch [Net.WebException] {
  $gate='TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  'RESULT=FAIL;STAGE=BITRIX24_REQUIRED_FIELD_COUNTS;GATE='+$gate
} catch {
  $msg=$_.Exception.Message
  $gate='COUNT_RUNTIME_ERROR'
  if($msg -match '^ODATA_([A-Z_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=BITRIX24_REQUIRED_FIELD_COUNTS;GATE='+$gate
}

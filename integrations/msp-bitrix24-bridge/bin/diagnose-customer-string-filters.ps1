#requires -version 2
# 1C TEST OData read-only diagnostic for HTTP 500 in string filters.
# Only integer $count responses, never any customer rows or identifiers.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
function ProbeCount([string]$Filter) {
  $resp=$null
  $reader=$null
  try {
    $base='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+[regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')+'/$count'
    $uri=$base+'?$filter='+[Uri]::EscapeDataString($Filter)
    $req=[Net.HttpWebRequest][Net.WebRequest]::Create($uri)
    $req.Method='GET'
    $req.Proxy=$null
    $req.AllowAutoRedirect=$false
    $req.Credentials=$Credential.GetNetworkCredential()
    $req.PreAuthenticate=$true
    $req.Timeout=15000
    $req.ReadWriteTimeout=15000
    $resp=$req.GetResponse()
    if([int]$resp.StatusCode -ne 200){return @{Status=('HTTP_'+[int]$resp.StatusCode)}}
    $reader=New-Object IO.StreamReader -ArgumentList @($resp.GetResponseStream(),[Text.Encoding]::ASCII)
    $raw=$reader.ReadToEnd().Trim()
    if($raw -notmatch '^[0-9]{1,12}$'){return @{Status='NON_NUMERIC_COUNT'}}
    $number=[long]0
    if(-not [long]::TryParse($raw,[ref]$number)){return @{Status='COUNT_PARSE_FAILED'}}
    return @{Status='HTTP_200';Count=$number}
  } catch [Net.WebException] {
    if($null -ne $_.Exception.Response){return @{Status=('HTTP_'+[int]$_.Exception.Response.StatusCode)}}
    return @{Status='TRANSPORT_ERROR'}
  } catch {
    return @{Status='REQUEST_RUNTIME_ERROR'}
  } finally {
    if($null -ne $reader){$reader.Close()}
    if($null -ne $resp){$resp.Close()}
  }
}
function ShowProbe([string]$Name,$Value) {
  'PROBE='+$Name+';STATUS='+$Value.Status
  if($Value.Status -eq 'HTTP_200'){'PROBE_COUNT='+$Name+';VALUE='+$Value.Count}
}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName){throw 'WRONG_HOST'}
  if($null -eq $Credential){$Credential=Get-Credential}
  if($null -eq $Credential){throw 'CREDENTIAL_REQUIRED'}
  $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
  $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
  $full=[regex]::Unescape('\u041d\u0430\u0438\u043c\u0435\u043d\u043e\u0432\u0430\u043d\u0438\u0435\u041f\u043e\u043b\u043d\u043e\u0435')
  $inn=[regex]::Unescape('\u0418\u041d\u041d')
  $base=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
  $baseline=ProbeCount $base
  ShowProbe 'BASELINE_BUYERS' $baseline
  if($baseline.Status -ne 'HTTP_200') {
    'RESULT=DIAGNOSTIC_COMPLETE;STAGE=BITRIX24_STRING_FILTERS;GATE=BASELINE_UNAVAILABLE'
  } else {
    $name=ProbeCount ($base+' and '+$full+" ne ''")
    ShowProbe 'FULL_NAME_NE_EMPTY' $name
    $tax=ProbeCount ($base+' and '+$inn+" ne ''")
    ShowProbe 'INN_NE_EMPTY' $tax
    if($name.Status -eq 'HTTP_200' -and $tax.Status -eq 'HTTP_200') {
      $both=ProbeCount ($base+' and '+$full+" ne '' and "+$inn+" ne ''")
      ShowProbe 'BOTH_NE_EMPTY' $both
      if($both.Status -eq 'HTTP_200' -and $both.Count -le $name.Count -and $both.Count -le $tax.Count -and $name.Count -le $baseline.Count -and $tax.Count -le $baseline.Count){
        'RESULT=PASS;STAGE=BITRIX24_STRING_FILTERS'
      } else {
        'RESULT=DIAGNOSTIC_COMPLETE;STAGE=BITRIX24_STRING_FILTERS;GATE=COMBINED_FILTER_UNAVAILABLE'
      }
    } else {
      'COMBINED_PROBE=SKIPPED'
      'RESULT=DIAGNOSTIC_COMPLETE;STAGE=BITRIX24_STRING_FILTERS;GATE=FIELD_FILTER_UNAVAILABLE'
    }
  }
} catch {
  'RESULT=FAIL;STAGE=BITRIX24_STRING_FILTERS;GATE=PRECHECK_OR_RUNTIME_ERROR'
} finally {
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'RAW_IDENTIFIERS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'BITRIX_CALLS=NO'
}

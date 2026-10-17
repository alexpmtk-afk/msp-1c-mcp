#requires -version 2
# Manual read-only OData integer counts by buyer category. TEST 1C SRV only.
# Native PowerShell 2 / ASCII source. No records, identifiers, or payloads emitted.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
function Probe([string]$Filter){
  $response=$null
  $reader=$null
  try{
    $uri=$script:base+'/$count?$filter='+[Uri]::EscapeDataString($Filter)
    $req=[Net.HttpWebRequest][Net.WebRequest]::Create($uri)
    $req.Method='GET'
    $req.Proxy=$null
    $req.AllowAutoRedirect=$false
    $req.PreAuthenticate=$true
    $req.Credentials=$Credential.GetNetworkCredential()
    $req.Timeout=20000
    $req.ReadWriteTimeout=20000
    $response=$req.GetResponse()
    if([int]$response.StatusCode -ne 200){return @{Status='HTTP_NOT_200'}}
    $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::ASCII)
    $raw=$reader.ReadToEnd().Trim()
    if($raw -notmatch '^[0-9]{1,8}$'){return @{Status='COUNT_FORMAT_INVALID'}}
    $n=[int]0
    if(-not [int]::TryParse($raw,[ref]$n)){return @{Status='COUNT_PARSE_FAILED'}}
    return @{Status='HTTP_200';Count=$n}
  }catch [Net.WebException]{
    if($null -ne $_.Exception.Response){
      return @{Status=('HTTP_'+[int]$_.Exception.Response.StatusCode)}
    }
    return @{Status='TRANSPORT_ERROR'}
  }catch{
    return @{Status='RUNTIME_ERROR'}
  }finally{
    if($null -ne $reader){$reader.Close()}
    if($null -ne $response){$response.Close()}
  }
}
function Show([string]$Name,$Result){
  'PROBE='+$Name+';STATUS='+$Result.Status
  if($Result.Status -eq 'HTTP_200'){'COUNT='+$Name+';VALUE='+$Result.Count}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){throw 'WRONG_HOST'}
  if($null -eq $Credential){
    $secure=Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString
    if($null -eq $secure -or $secure.Length -eq 0){throw 'PASSWORD_REQUIRED'}
    $Credential=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
    $secure=$null
  }
  if($Credential.UserName -ne 'MCP_OData_ReadOnly'){throw 'USERNAME_MISMATCH'}
  $table=[regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')
  $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
  $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
  $category=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u0424\u0438\u0437\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $legal=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $person=[regex]::Unescape('\u0424\u0438\u0437\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $inn=[regex]::Unescape('\u0418\u041d\u041d')
  $script:base='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$table
  $scope=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
  $baseline=Probe $scope
  Show 'BASELINE_ACTIVE_BUYERS' $baseline
  if($baseline.Status -ne 'HTTP_200' -or $baseline.Count -ne 6433){
    'RESULT=DIAGNOSTIC_COMPLETE;STAGE=BITRIX24_BUYER_CLASS_COUNTS;GATE=BASELINE_MISMATCH'
  }else{
    $legalFilter=$scope+' and '+$category+" eq '"+$legal+"'"
    $personFilter=$scope+' and '+$category+" eq '"+$person+"'"
    $a=Probe $legalFilter
    Show 'LEGAL_ENTITIES' $a
    $b=Probe $personFilter
    Show 'NATURAL_PERSONS' $b
    if($a.Status -eq 'HTTP_200' -and $b.Status -eq 'HTTP_200'){
      $other=$baseline.Count-$a.Count-$b.Count
      if($other -lt 0){
        'RESULT=FAIL;STAGE=BITRIX24_BUYER_CLASS_COUNTS;GATE=COUNTS_INCONSISTENT'
      }else{
        'OTHER_OR_UNCLASSIFIED='+$other
        $c=Probe ($legalFilter+' and '+$inn+" ne ''")
        Show 'LEGAL_WITH_NONEMPTY_INN' $c
        if($c.Status -eq 'HTTP_200' -and $c.Count -gt $a.Count){
          'RESULT=FAIL;STAGE=BITRIX24_BUYER_CLASS_COUNTS;GATE=LEGAL_INN_COUNT_INCONSISTENT'
        }elseif($c.Status -eq 'HTTP_200'){
          'CLASSIFICATION_COMPLETE='+($other -eq 0)
          'RESULT=PASS;STAGE=BITRIX24_BUYER_CLASS_COUNTS'
        }else{
          'RESULT=DIAGNOSTIC_COMPLETE;STAGE=BITRIX24_BUYER_CLASS_COUNTS;GATE=LEGAL_INN_FILTER_UNAVAILABLE'
        }
      }
    }else{
      'RESULT=DIAGNOSTIC_COMPLETE;STAGE=BITRIX24_BUYER_CLASS_COUNTS;GATE=CATEGORY_FILTER_UNAVAILABLE'
    }
  }
}catch{
  'RESULT=FAIL;STAGE=BITRIX24_BUYER_CLASS_COUNTS;GATE=PRECHECK_ERROR'
}finally{
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'RAW_IDENTIFIERS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'BITRIX_CALLS=NO'
  'SAFE_IDLE_TASK_UNCHANGED=YES'
  'NO_AUTOMATIC_RETRY=YES'
}

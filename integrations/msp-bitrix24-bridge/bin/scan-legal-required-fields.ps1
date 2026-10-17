#requires -version 2
# Legal-entity-only controlled scan on physical SRV. Read-only TEST 1C OData GET.
# Bounded, deterministic paging. No rows, IDs, names or INNs leave this process.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$response=$null
function Fail([string]$Code){throw ('ODATA_'+$Code)}
function NewRequest([string]$Url){
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($Url)
  $req.Method='GET'
  $req.Proxy=$null
  $req.AllowAutoRedirect=$false
  $req.PreAuthenticate=$true
  $req.Credentials=$Credential.GetNetworkCredential()
  $req.Timeout=20000
  $req.ReadWriteTimeout=20000
  return $req
}
function ReadCount([string]$Filter){
  $resp=$null;$reader=$null
  try{
    $uri=$script:base+'/$count?$filter='+[Uri]::EscapeDataString($Filter)
    $req=NewRequest $uri
    $resp=$req.GetResponse()
    if([int]$resp.StatusCode -ne 200){Fail 'COUNT_HTTP_NOT_200'}
    $reader=New-Object IO.StreamReader -ArgumentList @($resp.GetResponseStream(),[Text.Encoding]::ASCII)
    $value=$reader.ReadToEnd().Trim()
    if($value -notmatch '^[0-9]{1,8}$'){Fail 'COUNT_FORMAT_INVALID'}
    $parsed=[int]0
    if(-not [int]::TryParse($value,[ref]$parsed)){Fail 'COUNT_PARSE_ERROR'}
    return $parsed
  }finally{
    if($null -ne $reader){$reader.Close()}
    if($null -ne $resp){$resp.Close()}
  }
}
function ReadPage([string]$Filter,[int]$Skip,[int]$Top,[string]$Selected){
  $resp=$null;$reader=$null
  try{
    $uri=$script:base+'?$filter='+[Uri]::EscapeDataString($Filter)+
      '&$select='+[Uri]::EscapeDataString($Selected)+
      '&$orderby=Ref_Key%20asc&$top='+$Top+'&$skip='+$Skip
    $req=NewRequest $uri
    $req.Accept='application/atom+xml'
    $resp=$req.GetResponse()
    if([int]$resp.StatusCode -ne 200){Fail 'PAGE_HTTP_NOT_200'}
    $reader=New-Object IO.StreamReader -ArgumentList @($resp.GetResponseStream(),[Text.Encoding]::UTF8)
    $buf=New-Object char[] 8192
    $sb=New-Object Text.StringBuilder
    $length=0
    do{
      $n=$reader.Read($buf,0,$buf.Length)
      $length+=$n
      if($length -gt 3145728){Fail 'PAGE_TOO_LARGE'}
      if($n -gt 0){[void]$sb.Append($buf,0,$n)}
    }while($n -gt 0)
    $xml=New-Object Xml.XmlDocument
    $xml.XmlResolver=$null
    $xml.LoadXml($sb.ToString())
    if($xml.DocumentElement.LocalName -ne 'feed'){Fail 'PAGE_NOT_ATOM'}
    return @($xml.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']"))
  }finally{
    if($null -ne $reader){$reader.Close()}
    if($null -ne $resp){$resp.Close()}
  }
}
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
  $kind=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u0424\u0438\u0437\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $legal=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $script:base='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$name
  $filter=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false and '+$kind+" eq '"+$legal+"'"
  $selected='Ref_Key,'+$full+','+$inn
  $phase='COUNT_PRECHECK'
  $expected=ReadCount $filter
  if($expected -lt 1 -or $expected -gt 10000){Fail 'COUNT_OUTSIDE_SAFETY_LIMIT'}
  # Known acceptance count from the immediately preceding read-only check.
  if($expected -ne 1941){Fail 'LEGAL_BASELINE_COUNT_CHANGED'}
  $phase='PAGED_READ'
  $skip=0
  $top=100
  $pages=0
  $clock=[Diagnostics.Stopwatch]::StartNew()
  $totalPageMilliseconds=[long]0
  $maxPageMilliseconds=[long]0
  $seen=@{}
  $fullCount=0
  $innCount=0
  $bothCount=0
  $validInnCount=0
  while($skip -lt $expected){
    if($pages -ge 150){Fail 'PAGE_COUNT_LIMIT'}
    $pageClock=[Diagnostics.Stopwatch]::StartNew()
    $batch=@(ReadPage $filter $skip $top $selected)
    $pageClock.Stop()
    $totalPageMilliseconds+=$pageClock.ElapsedMilliseconds
    if($pageClock.ElapsedMilliseconds -gt $maxPageMilliseconds){$maxPageMilliseconds=$pageClock.ElapsedMilliseconds}
    $n=$batch.Count
    if($n -lt 1 -or $n -gt $top -or ($skip+$n) -gt $expected){Fail 'PAGE_ROW_COUNT_INVALID'}
    foreach($entry in $batch){
      $props=$entry.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
      if($null -eq $props){Fail 'PAGE_PROPERTIES_MISSING'}
      $id=$props.SelectSingleNode("./*[local-name()='Ref_Key']")
      $fullNode=$props.SelectSingleNode("./*[local-name()='"+$full+"']")
      $innNode=$props.SelectSingleNode("./*[local-name()='"+$inn+"']")
      if($null -eq $id -or $null -eq $fullNode -or $null -eq $innNode){Fail 'SELECTED_FIELDS_MISSING'}
      $guid=$id.InnerText.Trim().ToLowerInvariant()
      if($guid -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){Fail 'INVALID_GUID'}
      if($seen.ContainsKey($guid)){Fail 'DUPLICATE_GUID_ACROSS_PAGES'}
      $seen[$guid]=$true
      $nFull=($fullNode.InnerText.Trim().Length -gt 0)
      $tax=$innNode.InnerText.Trim()
      $nInn=($tax.Length -gt 0)
      if($nFull){$fullCount++}
      if($nInn){$innCount++}
      if($nFull -and $nInn){$bothCount++}
      if($tax -match '^(?:[0-9]{10}|[0-9]{12})$'){$validInnCount++}
    }
    $skip+=$n
    $pages++
    if(($pages % 10) -eq 0){'PROGRESS=PAGE_'+$pages+';PROCESSED='+$skip}
  }
  $phase='COUNT_POSTCHECK'
  $after=ReadCount $filter
  if($after -ne $expected -or $skip -ne $expected -or $seen.Count -ne $expected){Fail 'FINAL_COUNT_OR_UNIQUENESS_MISMATCH'}
  if($innCount -ne 1402){Fail 'LEGAL_INN_BASELINE_CHANGED'}
  $clock.Stop()
  if($bothCount -gt $fullCount -or $bothCount -gt $innCount){Fail 'RESULT_COUNTS_INCONSISTENT'}
  'COUNTERPARTIES_SCOPE=ACTIVE_LEGAL_BUYERS'
  'LEGAL_ENTITIES_TOTAL='+$expected
  'LEGAL_WITH_NONEMPTY_INN='+$innCount
  'LEGAL_WITH_FULL_NAME='+$fullCount
  'LEGAL_WITH_BOTH_REQUIRED='+$bothCount
  'ROWS_EXPECTED='+$expected
  'ROWS_SCANNED='+$skip
  'UNIQUE_GUIDS='+$seen.Count
  'PAGES='+$pages
  'SCAN_ELAPSED_SECONDS='+[Math]::Round($clock.Elapsed.TotalSeconds,2)
  'PAGE_REQUEST_TOTAL_MS='+$totalPageMilliseconds
  'PAGE_REQUEST_MAX_MS='+$maxPageMilliseconds
  'FULL_NAME_NONBLANK='+$fullCount
  'INN_NONBLANK='+$innCount
  'BOTH_NONBLANK='+$bothCount
  'INN_10_OR_12_DIGITS='+$validInnCount
  'MISSING_FULL_NAME='+($expected-$fullCount)
  'MISSING_INN='+($expected-$innCount)
  'MISSING_EITHER='+($expected-$bothCount)
  'ORGANIZATION_CLASSIFICATION=LEGAL_ONLY'
  'CUSTOMER_ROWS_PROCESSED_LOCALLY=YES'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'RAW_IDENTIFIERS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=BITRIX24_LEGAL_REQUIRED_FIELDS_SCAN'
}catch [Net.WebException]{
  $gate='TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  'RESULT=FAIL;STAGE=BITRIX24_LEGAL_REQUIRED_FIELDS_SCAN;GATE='+$gate
  'FAILURE_PHASE='+$phase
}catch{
  $msg=$_.Exception.Message
  $gate='LOCAL_RUNTIME_ERROR'
  if($msg -match '^ODATA_([A-Z_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=BITRIX24_LEGAL_REQUIRED_FIELDS_SCAN;GATE='+$gate
  'FAILURE_PHASE='+$phase
}finally{
  'READ_ONLY=YES'
  'NO_CUSTOMER_DATA_EXPORTED=YES'
  'NO_AUTOMATIC_RETRY=YES'
}

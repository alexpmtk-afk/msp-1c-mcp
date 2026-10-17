#requires -version 2
# S4 V3 READ-ONLY capability survey: 1C TEST OData $metadata only.
# No SelectChanges, no POST, no writes to SQLite/1C/Bitrix.
param([string]$ExpectedComputerName='SRV',[string]$OfflineFixturePath='')
$ErrorActionPreference='Stop'
$phase='HOST'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\exchange-plan-metadata-s4-v3.txt'
$encrypted=$null
$plain=$null
$secure=$null
$response=$null
function Fail([string]$Code){throw ('S4_'+$Code)}
function SafeName([string]$Value){
  if($Value.Length -gt 160){Fail 'PLAN_NAME_TOO_LONG'}
  $b=New-Object Text.StringBuilder
  foreach($ch in $Value.ToCharArray()){
    $num=[int]$ch
    if($num -ge 32 -and $num -le 126 -and $num -ne 92){
      [void]$b.Append($ch)
    }else{
      [void]$b.Append('\u'+$num.ToString('x4'))
    }
  }
  return $b.ToString()
}
function ParseMetadata([string]$XmlText){
  $settings=New-Object System.Xml.XmlReaderSettings
  $settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver=$null
  $settings.MaxCharactersInDocument=33554432
  $stringReader=New-Object System.IO.StringReader -ArgumentList $XmlText
  $xmlReader=$null
  try{
    $xmlReader=[System.Xml.XmlReader]::Create($stringReader,$settings)
    $xml=New-Object System.Xml.XmlDocument
    $xml.XmlResolver=$null
    $xml.Load($xmlReader)
  }finally{
    if($null -ne $xmlReader){$xmlReader.Close()}
    $stringReader.Close()
  }
  if($null -ne $xml.DocumentType){Fail 'DOCTYPE_NOT_ALLOWED'}
  # Explicit XmlNodeList indexing works consistently in old Windows PowerShell.
  $sets=$xml.SelectNodes("//*[local-name()='EntitySet']")
  if($null -eq $sets -or $sets.Count -lt 1 -or $sets.Count -gt 10000){Fail 'ENTITY_SET_COUNT_INVALID'}
  $plans=New-Object System.Collections.ArrayList
  $seen=@{}
  for($i=0;$i -lt $sets.Count;$i++){
    $node=$sets.Item($i)
    $a=$node.Attributes.GetNamedItem('Name')
    if($null -eq $a){Fail 'ENTITY_SET_NAME_MISSING'}
    $name=[string]$a.Value
    if($name -notlike 'ExchangePlan_*'){continue}
    if($name.Length -gt 160){Fail 'PLAN_NAME_TOO_LONG'}
    if($seen.ContainsKey($name)){Fail 'EXCHANGE_PLAN_DUPLICATE'}
    $seen[$name]=$true
    [void]$plans.Add($name)
    if($plans.Count -gt 100){Fail 'EXCHANGE_PLAN_LIMIT'}
  }
  $functions=$xml.SelectNodes("//*[local-name()='FunctionImport']")
  $select=$false
  $notify=$false
  if($null -ne $functions){
    for($i=0;$i -lt $functions.Count;$i++){
      $func=$functions.Item($i)
      $a=$func.Attributes.GetNamedItem('Name')
      if($null -eq $a){continue}
      if($a.Value -eq 'SelectChanges'){$select=$true}
      if($a.Value -eq 'NotifyChangesReceived'){$notify=$true}
    }
  }
  # Metadata declaration does not prove a working POST endpoint.
  return @{ EntitySets=[int]$sets.Count; PlanCount=[int]$plans.Count;
            Names=[string[]]@($plans.ToArray() | Sort-Object);
            SelectChangesDeclared=[bool]$select;
            NotifyChangesReceivedDeclared=[bool]$notify }
}

try{
  if($OfflineFixturePath -ne ''){
    if($env:CI -ne 'true'){Fail 'OFFLINE_FIXTURE_CI_ONLY'}
    if(-not [IO.File]::Exists($OfflineFixturePath)){Fail 'OFFLINE_FIXTURE_MISSING'}
    $phase='OFFLINE_XML_FIXTURE'
    $fixture=[IO.File]::ReadAllText($OfflineFixturePath,[Text.Encoding]::UTF8)
    if($fixture.Length -gt 33554432){Fail 'FIXTURE_TOO_LARGE'}
    $metadata=ParseMetadata $fixture
    'S4_ENTITY_SET_COUNT='+$metadata.EntitySets
    'S4_EXCHANGE_PLAN_SET_COUNT='+$metadata.PlanCount
    'S4_SELECTCHANGES_DECLARED='+$metadata.SelectChangesDeclared
    'S4_NOTIFYCHANGESRECEIVED_DECLARED='+$metadata.NotifyChangesReceivedDeclared
    'S4_NO_NETWORK=YES'
    'S4_NO_WRITES=YES'
    'RESULT=PASS;STAGE=SRV_ONEC_EXCHANGE_METADATA_SURVEY_V3_OFFLINE'
    exit 0
  }
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $cfg=Join-Path $root 'config\collector.ini'
  if(-not [IO.File]::Exists($secret) -or -not [IO.File]::Exists($cfg)){Fail 'MACHINE_CONFIG_MISSING'}
  if([IO.File]::Exists($status)){Fail 'SURVEY_ALREADY_EXISTS'}
  $settings=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($settings -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'NOT_SAFE_IDLE'}
  }
  $phase='SERVICE_DPAPI'
  Add-Type -AssemblyName System.Security
  $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
  $encrypted=[IO.File]::ReadAllBytes($secret)
  if($encrypted.Length -lt 32 -or $encrypted.Length -gt 8192){Fail 'CIPHERTEXT_SIZE'}
  $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'PASSWORD_SIZE'}
  $secure=New-Object Security.SecureString
  for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
  $secure.MakeReadOnly()
  [Array]::Clear($plain,0,$plain.Length)
  $plain=$null
  $credentials=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
  $phase='ODATA_METADATA_GET'
  $requestStart=[DateTime]::UtcNow
  $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/$metadata'
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET'
  $req.Accept='application/xml'
  $req.Proxy=$null
  $req.AllowAutoRedirect=$false
  $req.PreAuthenticate=$true
  $req.Credentials=$credentials.GetNetworkCredential()
  $req.Timeout=30000
  $req.ReadWriteTimeout=30000
  $response=$req.GetResponse()
  if([int]$response.StatusCode -ne 200){Fail 'METADATA_HTTP_NOT_200'}
  $phase='ODATA_METADATA_BODY'
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
  try{
    $buf=New-Object char[] 8192
    $text=New-Object Text.StringBuilder
    $size=0
    do{
      $n=$reader.Read($buf,0,$buf.Length)
      $size+=$n
      if($size -gt 33554432){Fail 'METADATA_OVER_32M'}
      if($n -gt 0){[void]$text.Append($buf,0,$n)}
    }while($n -gt 0)
  }finally{$reader.Close()}
  $phase='PARSE_EXCHANGE_PLANS'
  $metadata=ParseMetadata ($text.ToString())
  $plans=$metadata.Names
  $entityCount=$metadata.EntitySets
  $planCount=$metadata.PlanCount
  $selectChanges=$metadata.SelectChangesDeclared
  $notifyChanges=$metadata.NotifyChangesReceivedDeclared
  $phase='WRITE_METADATA_SUMMARY'
  $receipt=New-Object Text.StringBuilder
  [void]$receipt.AppendLine('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+
    ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;HTTP=200;ENTITY_SETS='+$entityCount+
    ';EXCHANGE_PLANS='+$planCount+';SELECTCHANGES_DECLARED='+$selectChanges+
    ';NOTIFYCHANGESRECEIVED_DECLARED='+$notifyChanges+
    ';ONEC_WRITES=0;BITRIX_CALLS=0')
  $ordered=@($plans | Sort-Object)
  for($i=0;$i -lt $ordered.Count;$i++){
    [void]$receipt.AppendLine(('PLAN_{0:D3}=' -f ($i+1))+(SafeName $ordered[$i]))
  }
  $fs=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
    $bytes=[Text.Encoding]::ASCII.GetBytes($receipt.ToString())
    $fs.Write($bytes,0,$bytes.Length)
    $fs.Flush()
  }finally{$fs.Close()}
  'S4_METADATA_HTTP=200'
  'S4_ENTITY_SETS='+$entityCount
  'S4_EXCHANGE_PLAN_SETS='+$planCount
  'S4_SELECTCHANGES_DECLARED='+$selectChanges
  'S4_NOTIFYCHANGESRECEIVED_DECLARED='+$notifyChanges
  'S4_PLAN_NAMES_SAVED_LOCALLY=YES'
  'S4_CHANGE_REGISTRATION_READY=NOT_PROVEN'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_ONEC_EXCHANGE_METADATA_SURVEY_V3'
}catch [Net.WebException]{
  $gate='ODATA_TRANSPORT_ERROR'
  $webStatus=([string]$_.Exception.Status).ToUpperInvariant()
  if($webStatus -match '^[A-Z_]{1,50}$'){$gate='ODATA_'+$webStatus}
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  $elapsedMs=-1
  if($null -ne $requestStart){$elapsedMs=[int]([DateTime]::UtcNow-$requestStart).TotalMilliseconds}
  try{
    if($OfflineFixturePath -eq ''){
      [IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate),[Text.Encoding]::ASCII)
    }
  }catch{}
  'S4_WEBEXCEPTION_STATUS='+$webStatus
  'S4_REQUEST_ELAPSED_MS='+$elapsedMs
  'RESULT=FAIL;STAGE=SRV_ONEC_EXCHANGE_METADATA_SURVEY_V3;GATE='+$gate+';PHASE='+$phase
  exit 1
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^S4_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  # Only safe exception type and XML position; never log exception messages or source records.
  $inner=$_.Exception
  # Windows PowerShell wraps XmlException in MethodInvocationException.
  for($i=0;$i -lt 6;$i++){
    if($null -eq $inner.InnerException){break}
    $inner=$inner.InnerException
  }
  $exceptionType=$inner.GetType().Name
  if($exceptionType -notmatch '^[A-Za-z0-9_]{1,80}$'){$exceptionType='UNKNOWN'}
  'S4_EXCEPTION_TYPE='+$exceptionType
  if($inner -is [System.Xml.XmlException]){
    'S4_XML_LINE='+[int]$inner.LineNumber
    'S4_XML_POSITION='+[int]$inner.LinePosition
  }
  try{
    if($OfflineFixturePath -eq ''){
      [IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate),[Text.Encoding]::ASCII)
    }
  }catch{}
  'RESULT=FAIL;STAGE=SRV_ONEC_EXCHANGE_METADATA_SURVEY_V3;GATE='+$gate+';PHASE='+$phase
  exit 1
}finally{
  if($null -ne $response){$response.Close()}
  if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
  if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
  if($null -ne $secure){$secure.Dispose()}
}

#requires -version 2
# TEST NewBase read-only metadata probe: contact information table-part fields only. No customer data.
# No SelectChanges, no POST, no writes to SQLite/1C/Bitrix.
param([string]$ExpectedComputerName='SRV',[string]$OfflineFixturePath='')
$ErrorActionPreference='Stop'
$phase='HOST'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\customer-phone-contactinfo-metadata-v3.txt'
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
function Attr($Node,[string]$Key){
 if($null -eq $Node){return ''}
 $a=$Node.Attributes.GetNamedItem($Key)
 if($null -eq $a){return ''}
 return [string]$a.Value
}
function LocalType([string]$Raw){
 $x=$Raw.Trim()
 if($x -match '^Collection\(([^)]+)\)$'){$x=$Matches[1]}
 $pos=$x.LastIndexOf('.')
 if($pos -ge 0){$x=$x.Substring($pos+1)}
 return $x
}
function ParseMetadata([string]$XmlText){
 $xmlSettings=New-Object System.Xml.XmlReaderSettings
 $xmlSettings.ProhibitDtd=$true
 $xmlSettings.XmlResolver=$null
 $xmlSettings.MaxCharactersInDocument=33554432
 $source=New-Object System.IO.StringReader -ArgumentList $XmlText
 $reader=$null
 try{
  $reader=[System.Xml.XmlReader]::Create($source,$xmlSettings)
  $xml=New-Object System.Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.Load($reader)
 }finally{if($null -ne $reader){$reader.Close()};$source.Close()}
 if($null -ne $xml.DocumentType){Fail 'DOCTYPE_REJECTED'}
 $sets=$xml.SelectNodes("//*[local-name()='EntitySet']")
 if($null -eq $sets -or $sets.Count -lt 1 -or $sets.Count -gt 10000){Fail 'ENTITY_SET_COUNT_INVALID'}
 $ownerName=[regex]::Unescape('Catalog_\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')
 $contact=[regex]::Unescape('\u041a\u043e\u043d\u0442\u0430\u043a\u0442\u043d\u0430\u044f\u0418\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f')
 $ownerSet=$null;$partSet=$null
 for($i=0;$i -lt $sets.Count;$i++){
  $node=$sets.Item($i)
  $name=Attr $node 'Name'
  if($name -eq $ownerName){if($null -ne $ownerSet){Fail 'OWNER_SET_DUPLICATE'};$ownerSet=$node}
  if($name -eq ($ownerName+'_'+$contact)){if($null -ne $partSet){Fail 'PART_SET_DUPLICATE'};$partSet=$node}
 }
 if($null -eq $ownerSet){Fail 'COUNTERPARTIES_ENTITY_SET_MISSING'}
 $types=$xml.SelectNodes("//*[local-name()='EntityType']")
 if($null -eq $types -or $types.Count -lt 1 -or $types.Count -gt 10000){Fail 'ENTITY_TYPE_COUNT_INVALID'}
 $ownerType=LocalType (Attr $ownerSet 'EntityType')
 $owner=$null;$part=$null;$partType=''
 foreach($node in $types){
  $name=Attr $node 'Name'
  if($name -eq $ownerType){if($null -ne $owner){Fail 'OWNER_TYPE_DUPLICATE'};$owner=$node}
 }
 if($null -eq $owner){Fail 'OWNER_TYPE_MISSING'}
 $navs=$owner.SelectNodes("./*[local-name()='NavigationProperty']")
 if($null -eq $navs){Fail 'OWNER_NAV_MISSING'}
 $candidateType=''
 foreach($nav in $navs){
  $name=Attr $nav 'Name'
  if($name -eq $contact -or $name -eq ('_'+$contact) -or $name -eq ($ownerName+'_'+$contact)){
   $candidateType=LocalType (Attr $nav 'Type')
   break
  }
 }
 $origin='UNRESOLVED'
 if($null -ne $partSet){
  $partType=LocalType (Attr $partSet 'EntityType')
  $origin='PART_ENTITY_SET'
 }elseif($candidateType -ne ''){
  $partType=$candidateType
  $origin='OWNER_NAVIGATION'
 }
 if($partType -eq ''){
  foreach($type in $types){
   $typeName=Attr $type 'Name'
   if($typeName -eq ($ownerName+'_'+$contact)){$partType=$typeName;$origin='TYPE_NAME'}
  }
 }
 if($partType -eq ''){Fail 'CONTACT_INFO_TYPE_NOT_RESOLVED'}
 foreach($node in $types){
  if((Attr $node 'Name') -eq $partType){
   if($null -ne $part){Fail 'PART_TYPE_DUPLICATE'}
   $part=$node
  }
 }
 if($null -eq $part){Fail 'CONTACT_INFO_TYPE_MISSING'}
 $props=$part.SelectNodes("./*[local-name()='Property']")
 if($null -eq $props -or $props.Count -lt 1 -or $props.Count -gt 100){Fail 'PART_PROPERTY_COUNT_INVALID'}
 $links=$part.SelectNodes("./*[local-name()='NavigationProperty']")
 if($null -ne $links -and $links.Count -gt 100){Fail 'PART_NAV_COUNT_INVALID'}
 $lines=New-Object Collections.ArrayList
 foreach($prop in $props){
  $key=Attr $prop 'Name';$typ=Attr $prop 'Type'
  if($key -eq '' -or $typ -eq ''){Fail 'PROPERTY_SIGNATURE_INVALID'}
  [void]$lines.Add('FIELD='+(SafeName $key)+';TYPE='+(SafeName $typ))
 }
 foreach($link in $links){
  $key=Attr $link 'Name'
  if($key -eq ''){Fail 'NAV_SIGNATURE_INVALID'}
  [void]$lines.Add('NAV='+(SafeName $key))
 }
 return @{ EntitySets=$sets.Count;OwnerNavs=$navs.Count;EntityType=(SafeName $partType);Properties=$props.Count;Navigations=$links.Count;Origin=$origin;Lines=$lines }
}

try{
 if($OfflineFixturePath -ne ''){
  if($env:CI -ne 'true'){Fail 'OFFLINE_TEST_CI_ONLY'}
  if(-not [IO.File]::Exists($OfflineFixturePath)){Fail 'OFFLINE_FIXTURE_MISSING'}
  $fixture=[IO.File]::ReadAllText($OfflineFixturePath,[Text.Encoding]::UTF8)
  $parsed=ParseMetadata $fixture
  'PHONE_OFFLINE_ORIGIN='+$parsed.Origin
  'PHONE_OFFLINE_PROPERTIES='+$parsed.Properties
  foreach($line in $parsed.Lines){Write-Output $line}
  'RESULT=PASS;STAGE=PHONE_METADATA_V3_OFFLINE'
  exit 0
 }
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $cfg=Join-Path $root 'config\collector.ini'
  if(-not [IO.File]::Exists($secret) -or -not [IO.File]::Exists($cfg)){Fail 'MACHINE_CONFIG_MISSING'}
  if([IO.File]::Exists($status)){Fail 'PHONE_V3_ALREADY_EXISTS'}
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
  $phase='PARSE_CONTACTINFO_METADATA'
  $metadata=ParseMetadata ($text.ToString())
  $phase='WRITE_READONLY_RECEIPT'
  $receipt=New-Object Text.StringBuilder
  [void]$receipt.AppendLine('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;ENTITY_SETS='+$metadata.EntitySets+';CONTACTINFO_SET=YES;ORIGIN='+$metadata.Origin+';ENTITY_TYPE='+$metadata.EntityType+';PROPERTIES='+$metadata.Properties+';NAVIGATIONS='+$metadata.Navigations+';ONEC_WRITES=0;BITRIX_REQUESTS=0;CUSTOMER_DATA_EXPORTED=0')
  foreach($line in $metadata.Lines){[void]$receipt.AppendLine($line)}
  $f=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$bytes=[Text.Encoding]::ASCII.GetBytes($receipt.ToString());$f.Write($bytes,0,$bytes.Length);$f.Flush()}finally{$f.Close()}
  'PHONE_METADATA_ENTITY_SET=PASS'
  'PHONE_METADATA_ORIGIN='+$metadata.Origin
  'PHONE_METADATA_PROPERTIES='+$metadata.Properties
  'PHONE_METADATA_NAVIGATIONS='+$metadata.Navigations
  'PHONE_METADATA_REPORT='+$status
  'ONEC_WRITES=0'
  'BITRIX_REQUESTS=0'
  'RESULT=PASS;STAGE=TEST_NEWBASE_CONTACTINFO_METADATA_READONLY_V3'

}catch [Net.WebException]{
  $gate='ODATA_TRANSPORT_ERROR'
  $webStatus=([string]$_.Exception.Status).ToUpperInvariant()
  if($webStatus -match '^[A-Z_]{1,50}$'){$gate='ODATA_'+$webStatus}
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  $elapsedMs=-1
  if($null -ne $requestStart){$elapsedMs=[int]([DateTime]::UtcNow-$requestStart).TotalMilliseconds}
  try{
    if($OfflineFixturePath -eq ''){
      [IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';EXCEPTION_TYPE='+$exceptionType+';ERROR_ID='+([string]$_.FullyQualifiedErrorId -replace '[^A-Za-z0-9_.]','_')+';ERROR_LINE='+[int]$_.InvocationInfo.ScriptLineNumber),[Text.Encoding]::ASCII)
    }
  }catch{}
  'PHONE_WEBEXCEPTION_STATUS='+$webStatus
  'PHONE_REQUEST_ELAPSED_MS='+$elapsedMs
  'RESULT=FAIL;STAGE=TEST_NEWBASE_CONTACTINFO_METADATA_READONLY_V3;GATE='+$gate+';PHASE='+$phase
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
  'PHONE_EXCEPTION_TYPE='+$exceptionType
  'PHONE_ERROR_ID='+([string]$_.FullyQualifiedErrorId -replace '[^A-Za-z0-9_.]','_')
  'PHONE_ERROR_LINE='+[int]$_.InvocationInfo.ScriptLineNumber
  if($inner -is [System.Xml.XmlException]){
    'PHONE_XML_LINE='+[int]$inner.LineNumber
    'PHONE_XML_POSITION='+[int]$inner.LinePosition
  }
  try{
    if($OfflineFixturePath -eq ''){
      [IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';EXCEPTION_TYPE='+$exceptionType+';ERROR_ID='+([string]$_.FullyQualifiedErrorId -replace '[^A-Za-z0-9_.]','_')+';ERROR_LINE='+[int]$_.InvocationInfo.ScriptLineNumber),[Text.Encoding]::ASCII)
    }
  }catch{}
  'RESULT=FAIL;STAGE=TEST_NEWBASE_CONTACTINFO_METADATA_READONLY_V3;GATE='+$gate+';PHASE='+$phase
  exit 1
}finally{
  if($null -ne $response){$response.Close()}
  if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
  if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
  if($null -ne $secure){$secure.Dispose()}
}

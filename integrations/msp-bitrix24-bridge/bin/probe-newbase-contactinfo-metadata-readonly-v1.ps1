#requires -version 2
# TEST NewBase read-only metadata probe: contact information table-part fields only. No customer data.
# No SelectChanges, no POST, no writes to SQLite/1C/Bitrix.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='HOST'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\customer-phone-contactinfo-metadata-v1.txt'
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
 $readerSource=New-Object IO.StringReader -ArgumentList $XmlText
 $reader=$null
 try{
  $reader=[Xml.XmlReader]::Create($readerSource,$settings)
  $xml=New-Object Xml.XmlDocument;$xml.XmlResolver=$null;$xml.Load($reader)
 }finally{if($null -ne $reader){$reader.Close()};$readerSource.Close()}
 if($null -ne $xml.DocumentType){Fail 'DOCTYPE_REJECTED'}
 $sets=$xml.SelectNodes("//*[local-name()='EntitySet']")
 if($null -eq $sets -or $sets.Count -lt 100 -or $sets.Count -gt 10000){Fail 'ENTITY_SETS_UNEXPECTED'}
 $target=[regex]::Unescape('Catalog_\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b_\u041a\u043e\u043d\u0442\u0430\u043a\u0442\u043d\u0430\u044f\u0418\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f')
 $matched=$null
 for($i=0;$i -lt $sets.Count;$i++){
  $node=$sets.Item($i);$a=$node.Attributes.GetNamedItem('Name')
  if($null -ne $a -and $a.Value -eq $target){
   if($null -ne $matched){Fail 'DUPLICATE_TARGET_ENTITY_SET'}
   $matched=$node
  }
 }
 if($null -eq $matched){Fail 'CONTACTINFO_ENTITY_SET_MISSING'}
 $attr=$matched.Attributes.GetNamedItem('EntityType')
 if($null -eq $attr){Fail 'ENTITY_TYPE_REFERENCE_MISSING'}
 $typename=[string]$attr.Value
 $localName=$typename.Substring($typename.LastIndexOf('.')+1)
 $types=$xml.SelectNodes("//*[local-name()='EntityType']")
 $record=$null
 foreach($type in $types){
  $name=$type.Attributes.GetNamedItem('Name')
  if($null -ne $name -and $name.Value -eq $localName){
   if($null -ne $record){Fail 'DUPLICATE_ENTITY_TYPE'}
   $record=$type
  }
 }
 if($null -eq $record){Fail 'ENTITY_TYPE_NOT_FOUND'}
 $props=$record.SelectNodes("./*[local-name()='Property']")
 $navs=$record.SelectNodes("./*[local-name()='NavigationProperty']")
 if($null -eq $props -or $props.Count -lt 1 -or $props.Count -gt 100){Fail 'PROPERTY_COUNT_INVALID'}
 if($null -ne $navs -and $navs.Count -gt 100){Fail 'NAVIGATION_COUNT_INVALID'}
 $lines=New-Object Collections.ArrayList
 foreach($prop in $props){
  $nm=$prop.Attributes.GetNamedItem('Name')
  $ty=$prop.Attributes.GetNamedItem('Type')
  if($null -eq $nm -or $null -eq $ty){Fail 'PROPERTY_SIGNATURE_INVALID'}
  [void]$lines.Add('FIELD='+ (SafeName ([string]$nm.Value)) + ';TYPE='+(SafeName ([string]$ty.Value)))
 }
 foreach($nav in $navs){
  $nm=$nav.Attributes.GetNamedItem('Name')
  if($null -eq $nm){Fail 'NAVIGATION_SIGNATURE_INVALID'}
  [void]$lines.Add('NAV='+ (SafeName ([string]$nm.Value)))
 }
 return @{EntitySets=$sets.Count;EntityType=(SafeName $localName);Properties=$props.Count;Navigations=$navs.Count;Lines=$lines}
}

try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $cfg=Join-Path $root 'config\collector.ini'
  if(-not [IO.File]::Exists($secret) -or -not [IO.File]::Exists($cfg)){Fail 'MACHINE_CONFIG_MISSING'}
  if([IO.File]::Exists($status)){Fail 'PHONE_PROBE_ALREADY_EXISTS'}
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
  [void]$receipt.AppendLine('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;ENTITY_SETS='+$metadata.EntitySets+';CONTACTINFO_SET=YES;ENTITY_TYPE='+$metadata.EntityType+';PROPERTIES='+$metadata.Properties+';NAVIGATIONS='+$metadata.Navigations+';ONEC_WRITES=0;BITRIX_REQUESTS=0;CUSTOMER_DATA_EXPORTED=0')
  foreach($line in $metadata.Lines){[void]$receipt.AppendLine($line)}
  $f=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$bytes=[Text.Encoding]::ASCII.GetBytes($receipt.ToString());$f.Write($bytes,0,$bytes.Length);$f.Flush()}finally{$f.Close()}
  'PHONE_METADATA_ENTITY_SET=PASS'
  'PHONE_METADATA_PROPERTIES='+$metadata.Properties
  'PHONE_METADATA_NAVIGATIONS='+$metadata.Navigations
  'PHONE_METADATA_REPORT='+$status
  'ONEC_WRITES=0'
  'BITRIX_REQUESTS=0'
  'RESULT=PASS;STAGE=TEST_NEWBASE_CONTACTINFO_METADATA_READONLY'

}catch [Net.WebException]{
  $gate='ODATA_TRANSPORT_ERROR'
  $webStatus=([string]$_.Exception.Status).ToUpperInvariant()
  if($webStatus -match '^[A-Z_]{1,50}$'){$gate='ODATA_'+$webStatus}
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  $elapsedMs=-1
  if($null -ne $requestStart){$elapsedMs=[int]([DateTime]::UtcNow-$requestStart).TotalMilliseconds}
  try{
    if($true){
      [IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate),[Text.Encoding]::ASCII)
    }
  }catch{}
  'PHONE_WEBEXCEPTION_STATUS='+$webStatus
  'PHONE_REQUEST_ELAPSED_MS='+$elapsedMs
  'RESULT=FAIL;STAGE=TEST_NEWBASE_CONTACTINFO_METADATA_READONLY;GATE='+$gate+';PHASE='+$phase
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
  if($inner -is [System.Xml.XmlException]){
    'PHONE_XML_LINE='+[int]$inner.LineNumber
    'PHONE_XML_POSITION='+[int]$inner.LinePosition
  }
  try{
    if($true){
      [IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate),[Text.Encoding]::ASCII)
    }
  }catch{}
  'RESULT=FAIL;STAGE=TEST_NEWBASE_CONTACTINFO_METADATA_READONLY;GATE='+$gate+';PHASE='+$phase
  exit 1
}finally{
  if($null -ne $response){$response.Close()}
  if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
  if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
  if($null -ne $secure){$secure.Dispose()}
}

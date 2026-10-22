#requires -version 2
# One-shot, metadata-only 1C TEST NewBase customer order survey.
# No customer/order rows, no OData POST/PATCH/DELETE, no CRM, no SQLite reads or writes.
param([string]$ExpectedComputerName='SRV',[string]$OfflineFixturePath='')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\bitrix-to-onec-customer-order-metadata-v1.txt'
$phase='HOST';$encrypted=$null;$plain=$null;$response=$null
function Fail([string]$Code){throw ('ONEC_ORDER_META_'+$Code)}
function Need([bool]$Condition,[string]$Code){if(-not $Condition){Fail $Code}}
function Attr($Node,[string]$Key){
 if($null -eq $Node){return ''}
 $a=$Node.Attributes.GetNamedItem($Key)
 if($null -eq $a){return ''}
 return [string]$a.Value
}
function LastType([string]$FullName){
 $s=$FullName.Trim()
 if($s -match '^Collection\((.+)\)$'){$s=$Matches[1]}
 $pos=$s.LastIndexOf('.')
 if($pos -ge 0){$s=$s.Substring($pos+1)}
 return $s
}
function Safe([string]$Value){
 Need ($Value.Length -le 200) 'METADATA_NAME_TOO_LONG'
 $b=New-Object Text.StringBuilder
 foreach($ch in $Value.ToCharArray()){
  $n=[int]$ch
  if($n -ge 32 -and $n -le 126 -and $n -ne 59 -and $n -ne 92){
   [void]$b.Append($ch)
  }else{[void]$b.Append(('\u{0:x4}' -f $n))}
 }
 return $b.ToString()
}
function Field($Node,[string]$Tag){
 $res=New-Object Collections.ArrayList
 if($null -eq $Node){return ,$res}
 foreach($item in $Node.SelectNodes("./*[local-name()='"+$Tag+"']")){
  $name=Attr $item 'Name';$type=Attr $item 'Type'
  Need ($name -ne '') 'UNNAMED_XML_MEMBER'
  [void]$res.Add(@{Name=$name;Type=$type})
 }
 return ,$res
}
function Parse([string]$XmlText){
 $settings=New-Object Xml.XmlReaderSettings
 $settings.ProhibitDtd=$true
 $settings.XmlResolver=$null
 $settings.MaxCharactersInDocument=33554432
 $sr=New-Object IO.StringReader -ArgumentList $XmlText
 $xr=$null
 try{
  $xr=[Xml.XmlReader]::Create($sr,$settings)
  $xml=New-Object Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.Load($xr)
 }finally{if($null -ne $xr){$xr.Close()};$sr.Close()}
 Need ($null -eq $xml.DocumentType) 'DOCTYPE_DENIED'
 $sets=$xml.SelectNodes("//*[local-name()='EntitySet']")
 $types=$xml.SelectNodes("//*[local-name()='EntityType']")
 Need ($null -ne $sets -and $sets.Count -ge 1 -and $sets.Count -le 10000) 'SETS_COUNT'
 Need ($null -ne $types -and $types.Count -ge 1 -and $types.Count -le 10000) 'TYPES_COUNT'
 $typeIndex=@{};$setIndex=@{}
 foreach($t in $types){
  $name=Attr $t 'Name'
  Need ($name -ne '' -and -not $typeIndex.ContainsKey($name)) 'DUPLICATE_TYPE'
  $typeIndex[$name]=$t
 }
 foreach($x in $sets){
  $name=Attr $x 'Name'
  Need ($name -ne '' -and -not $setIndex.ContainsKey($name)) 'DUPLICATE_SET'
  $setIndex[$name]=$x
 }
 $baseCandidates=New-Object Collections.ArrayList
 foreach($set in $sets){
  $name=Attr $set 'Name'
  if(-not $name.StartsWith('Document_')){continue}
  if(($name -notmatch '\u0417\u0430\u043a\u0430\u0437') -or ($name -notmatch '\u041f\u043e\u043a\u0443\u043f')){continue}
  $type=LastType (Attr $set 'EntityType')
  Need ($typeIndex.ContainsKey($type)) 'DOCUMENT_TYPE_MISSING'
  $node=$typeIndex[$type]
  $props=Field $node 'Property'
  $names=@{};foreach($p in $props){$names[$p.Name]=$true}
  # Root document, not its tabular part: it has standard Number, Date and Ref_Key.
  if($names.ContainsKey('Ref_Key') -and $names.ContainsKey('Number') -and $names.ContainsKey('Date')){
   [void]$baseCandidates.Add(@{Name=$name;Type=$type;Node=$node})
  }
 }
 $lines=New-Object Collections.ArrayList
 [void]$lines.Add('ENTITY_SETS='+$sets.Count)
 [void]$lines.Add('ROOT_ORDER_CANDIDATES='+$baseCandidates.Count)
 Need ($baseCandidates.Count -le 8) 'TOO_MANY_ORDER_CANDIDATES'
 foreach($candidate in $baseCandidates){
  $rootName=[string]$candidate.Name;$rootType=[string]$candidate.Type
  [void]$lines.Add('DOCUMENT_SET='+(Safe $rootName))
  [void]$lines.Add('DOCUMENT_TYPE='+(Safe $rootType))
  $fields=Field $candidate.Node 'Property';$navs=Field $candidate.Node 'NavigationProperty'
  Need ($fields.Count -le 250 -and $navs.Count -le 100) 'DOCUMENT_FIELD_OVERFLOW'
  [void]$lines.Add('DOCUMENT_FIELDS='+$fields.Count)
  foreach($p in $fields){[void]$lines.Add('DOC_FIELD='+(Safe $p.Name)+';TYPE='+(Safe $p.Type))}
  [void]$lines.Add('DOCUMENT_NAVIGATIONS='+$navs.Count)
  foreach($n in $navs){[void]$lines.Add('DOC_NAV='+(Safe $n.Name)+';TYPE='+(Safe $n.Type))}
  $partCount=0
  foreach($partSet in $sets){
   $pn=Attr $partSet 'Name'
   if(-not $pn.StartsWith($rootName+'_')){continue}
   $pt=LastType (Attr $partSet 'EntityType')
   Need ($typeIndex.ContainsKey($pt)) 'PART_TYPE_MISSING'
   $partCount++
   Need ($partCount -le 20) 'TOO_MANY_PARTS'
   $partFields=Field $typeIndex[$pt] 'Property'
   Need ($partFields.Count -le 150) 'PART_FIELD_OVERFLOW'
   [void]$lines.Add('PART_SET='+(Safe $pn))
   [void]$lines.Add('PART_TYPE='+(Safe $pt))
   [void]$lines.Add('PART_FIELDS='+$partFields.Count)
   foreach($p in $partFields){[void]$lines.Add('PART_FIELD='+(Safe $p.Name)+';TYPE='+(Safe $p.Type))}
  }
  [void]$lines.Add('RELATED_PART_SETS='+$partCount)
 }
 [void]$lines.Add('RESULT=PASS;STAGE=ONEC_CUSTOMER_ORDER_METADATA_READONLY_V1')
 return ,$lines
}
try{
 if($OfflineFixturePath -ne ''){
  Need ($env:CI -eq 'true') 'OFFLINE_CI_ONLY'
  Need ([IO.File]::Exists($OfflineFixturePath)) 'OFFLINE_FIXTURE_MISSING'
  $fixture=[IO.File]::ReadAllText($OfflineFixturePath,[Text.Encoding]::UTF8)
  $parsed=Parse $fixture
  foreach($line in $parsed){Write-Output $line}
  exit 0
 }
 Need ($ExpectedComputerName -eq 'SRV' -and $env:COMPUTERNAME -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 $config=Join-Path $root 'config\collector.ini'
 Need ([IO.File]::Exists($secret) -and [IO.File]::Exists($config)) 'MISSING_MACHINE_CONFIG'
 Need (-not [IO.File]::Exists($status)) 'STATUS_ALREADY_EXISTS'
 foreach($f in @($secret,$config)){
  Need (([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
 }
 $flags=[IO.File]::ReadAllText($config,[Text.Encoding]::ASCII)
 foreach($key in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  Need ($flags -match ('(?m)^'+[regex]::Escape($key)+'\r?$')) 'LEGACY_CONFIG_CHANGED'
 }
 $phase='DECRYPT'
 Add-Type -AssemblyName System.Security
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
 $encrypted=[IO.File]::ReadAllBytes($secret)
 Need ($encrypted.Length -ge 32 -and $encrypted.Length -le 8192) 'CIPHERTEXT_SIZE'
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 Need ($plain.Length -ge 2 -and $plain.Length -le 1024 -and ($plain.Length % 2) -eq 0) 'PASSWORD_SIZE'
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
 $secure.MakeReadOnly()
 [Array]::Clear($plain,0,$plain.Length);$plain=$null
 $cred=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
 $phase='METADATA_GET'
 $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/$metadata'
 $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
 $req.Method='GET';$req.Accept='application/xml';$req.Proxy=$null
 $req.AllowAutoRedirect=$false;$req.PreAuthenticate=$true
 $req.Credentials=$cred.GetNetworkCredential()
 $req.Timeout=60000;$req.ReadWriteTimeout=60000
 $response=$req.GetResponse()
 Need ([int]$response.StatusCode -eq 200) 'METADATA_HTTP_NON200'
 $phase='READ_METADATA'
 $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
 try{
  $buffer=New-Object char[] 8192
  $data=New-Object Text.StringBuilder
  $length=0
  do{
   $n=$reader.Read($buffer,0,$buffer.Length)
   $length+=$n
   Need ($length -le 33554432) 'METADATA_TOO_BIG'
   if($n -gt 0){[void]$data.Append($buffer,0,$n)}
  }while($n -gt 0)
 }finally{$reader.Close()}
 $phase='PARSE_METADATA'
 $parsed=Parse ($data.ToString())
 $phase='SAVE_RECEIPT'
 $text=New-Object Text.StringBuilder
 [void]$text.AppendLine('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;SOURCE=TEST_NEWBASE;GET_ONLY=YES')
 foreach($line in $parsed){[void]$text.AppendLine($line)}
 $fs=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{
  $bytes=[Text.Encoding]::ASCII.GetBytes($text.ToString())
  $fs.Write($bytes,0,$bytes.Length);$fs.Flush()
 }finally{$fs.Close()}
 foreach($line in $parsed){Write-Output $line}
 'ODATA_METHOD=GET;ONEC_WRITES=0;CRM_REQUESTS=0;SQLITE_WRITES=0'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^ONEC_ORDER_META_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 $type=$_.Exception.GetType().Name
 if($null -ne $response){try{$response.Close()}catch{}}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
 if($OfflineFixturePath -eq '' -and $phase -ne 'HOST'){
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';TYPE='+$type),[Text.Encoding]::ASCII)}catch{}
 }
 'RESULT=FAIL;STAGE=ONEC_CUSTOMER_ORDER_METADATA_READONLY_V1;PHASE='+$phase+';GATE='+$gate+';TYPE='+$type
 exit 1
}finally{
 if($null -ne $response){try{$response.Close()}catch{}}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
}

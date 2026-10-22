#requires -version 2
# One TEST NewBase OData GET: 1 stock row from 1C Customer Order. Absolutely no data values in output.
# No POST/PATCH/DELETE, no CRM calls, no customer SQLite changes, no live order mutations.
param([string]$ExpectedComputerName='SRV',[string]$OfflineFixturePath='')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\bitrix-to-onec-stock-row-readonly-v2.txt'
$phase='HOST';$plain=$null;$response=$null
function Fail([string]$Code){throw ('ONEC_STOCK_ROW_'+$Code)}
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function Field($Props,[string]$Name){
 $node=$Props.SelectSingleNode("./*[local-name()='"+$Name+"']")
 if($null -eq $node){return @{Present=$false;Value=''}}
 return @{Present=$true;Value=[string]$node.InnerText}
}
function Yes([bool]$Bool){if($Bool){return 'YES'}else{return 'NO'}}
function ShortClass([string]$Val){
 $v=$Val.Trim()
 if($v -eq ''){return 'EMPTY'}
 if($v -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'){return 'GUID_TEXT'}
 if($v -match '^\{[0-9a-fA-F\-]{36}\}$'){return 'BRACED_GUID'}
 if($v -match '^(?i:Catalog|StandardODATA|Enum)\.[A-Za-z0-9_.]+$'){return 'TECHNICAL_LITERAL'}
 return 'OPAQUE_STRING'
}
function TypeFamily([string]$Val){
 $v=$Val.Trim()
 if($v -eq ''){return 'EMPTY'}
 if($v -match '(^|\.)Catalog_[\p{L}\p{N}_]+$'){return 'CATALOG'}
 if($v -match '(^|\.)Enum_[\p{L}\p{N}_]+$'){return 'ENUM'}
 if($v -match '(^|\.)Document_[\p{L}\p{N}_]+$'){return 'DOCUMENT'}
 return 'OTHER'
}
function ExpectedNomenclature([string]$Val){
 $expected='(^|\.)Catalog_'+[regex]::Unescape('\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430')+'$'
 return (Yes ($Val.Trim() -match $expected))
}
function GuidState([string]$Val){
 $v=$Val.Trim()
 if($v -eq ''){return 'EMPTY'}
 if($v -notmatch '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$'){return 'OTHER'}
 if($v -eq '00000000-0000-0000-0000-000000000000'){return 'ZERO_GUID'}
 return 'NONZERO_GUID'
}
function NumericClass([string]$Val){
 if($Val.Trim() -eq ''){return 'EMPTY'}
 $v=0.0
 if([double]::TryParse($Val,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$v)){
  if($v -gt 0){return 'POSITIVE'}
  if($v -eq 0){return 'ZERO'}
  return 'NEGATIVE'
 }
 return 'NON_NUMERIC'
}
function Analyze([string]$Body){
 $settings=New-Object Xml.XmlReaderSettings
 $settings.ProhibitDtd=$true;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=4194304
 $sr=New-Object IO.StringReader -ArgumentList $Body
 $reader=$null
 try{$reader=[Xml.XmlReader]::Create($sr,$settings);$xml=New-Object Xml.XmlDocument;$xml.XmlResolver=$null;$xml.Load($reader)}
 finally{if($null -ne $reader){$reader.Close()};$sr.Close()}
 Need ($null -eq $xml.DocumentType) 'DOCTYPE_DENIED'
 Need ($xml.DocumentElement.LocalName -eq 'feed') 'NOT_ATOM_FEED'
 $entries=$xml.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']")
 Need ($null -ne $entries -and $entries.Count -le 1) 'TOO_MANY_ENTRIES'
 $lines=New-Object Collections.ArrayList
 [void]$lines.Add('ATOM_ENTRIES='+$entries.Count)
 if($entries.Count -eq 0){
  [void]$lines.Add('ROW_FOUND=NO')
  [void]$lines.Add('RESULT=PARTIAL;STAGE=ONEC_STOCK_ROW_READONLY_V2;GATE=NO_EXISTING_ROWS')
  return ,$lines
 }
 $props=$entries.Item(0).SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
 Need ($null -ne $props) 'ATOM_PROPERTIES_MISSING'
 $nom=Field $props ([regex]::Unescape('\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430'))
 $typ=Field $props ([regex]::Unescape('\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430_Type'))
 $unit=Field $props ([regex]::Unescape('\u0415\u0434\u0438\u043d\u0438\u0446\u0430\u0418\u0437\u043c\u0435\u0440\u0435\u043d\u0438\u044f'))
 $unitType=Field $props ([regex]::Unescape('\u0415\u0434\u0438\u043d\u0438\u0446\u0430\u0418\u0437\u043c\u0435\u0440\u0435\u043d\u0438\u044f_Type'))
 $q=Field $props ([regex]::Unescape('\u041a\u043e\u043b\u0438\u0447\u0435\u0441\u0442\u0432\u043e'))
 $price=Field $props ([regex]::Unescape('\u0426\u0435\u043d\u0430'))
 $ref=Field $props 'Ref_Key'
 $line=Field $props 'LineNumber'
 Need ($nom.Present -and $typ.Present -and $q.Present -and $price.Present -and $ref.Present -and $line.Present) 'EXPECTED_COLUMN_MISSING'
 [void]$lines.Add('ROW_FOUND=YES')
 [void]$lines.Add('REF_KEY_CLASS='+(ShortClass $ref.Value))
 [void]$lines.Add('LINE_NUMBER_CLASS='+(NumericClass $line.Value))
 [void]$lines.Add('NOMENCLATURE_CLASS='+(ShortClass $nom.Value))
 [void]$lines.Add('NOMENCLATURE_TYPE_CLASS='+(ShortClass $typ.Value))
 [void]$lines.Add('NOMENCLATURE_TYPE_PRESENT='+(Yes ($typ.Value.Trim() -ne '')))
 [void]$lines.Add('NOMENCLATURE_TYPE_FAMILY='+(TypeFamily $typ.Value))
 [void]$lines.Add('NOMENCLATURE_TYPE_EXPECTED='+(ExpectedNomenclature $typ.Value))
 [void]$lines.Add('UNIT_CLASS='+(ShortClass $unit.Value))
 [void]$lines.Add('UNIT_TYPE_CLASS='+(ShortClass $unitType.Value))
 [void]$lines.Add('UNIT_TYPE_FAMILY='+(TypeFamily $unitType.Value))
 [void]$lines.Add('QTY_CLASS='+(NumericClass $q.Value))
 [void]$lines.Add('PRICE_CLASS='+(NumericClass $price.Value))
 $characteristic=Field $props ([regex]::Unescape('\u0425\u0430\u0440\u0430\u043a\u0442\u0435\u0440\u0438\u0441\u0442\u0438\u043a\u0430_Key'))
 [void]$lines.Add('CHARACTERISTIC_PRESENT='+(Yes ($characteristic.Value.Trim() -ne '')))
 [void]$lines.Add('CHARACTERISTIC_GUID_STATE='+(GuidState $characteristic.Value))
 $vat=Field $props ([regex]::Unescape('\u0421\u0442\u0430\u0432\u043a\u0430\u041d\u0414\u0421_Key'))
 [void]$lines.Add('VAT_RATE_PRESENT='+(Yes ($vat.Value.Trim() -ne '')))
 [void]$lines.Add('VAT_RATE_GUID_STATE='+(GuidState $vat.Value))
 [void]$lines.Add('RESULT=PASS;STAGE=ONEC_STOCK_ROW_READONLY_V2')
 return ,$lines
}
try{
 if($OfflineFixturePath -ne ''){
  Need ($env:CI -eq 'true') 'OFFLINE_CI_ONLY'
  Need ([IO.File]::Exists($OfflineFixturePath)) 'OFFLINE_FIXTURE_MISSING'
  foreach($line in (Analyze ([IO.File]::ReadAllText($OfflineFixturePath,[Text.Encoding]::UTF8)))){Write-Output $line}
  exit 0
 }
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 $cfg=Join-Path $root 'config\collector.ini';$secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 Need ([IO.File]::Exists($cfg) -and [IO.File]::Exists($secret)) 'MACHINE_CONFIG_MISSING'
 Need (-not [IO.File]::Exists($status)) 'ALREADY_RUN'
 $flags=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
 foreach($key in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  Need ($flags -match ('(?m)^'+[regex]::Escape($key)+'\r?$')) 'LEGACY_FLAGS_CHANGED'
 }
 $phase='AUTH_LOCAL'
 Add-Type -AssemblyName System.Security
 $salt=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
 $encrypted=[IO.File]::ReadAllBytes($secret)
 Need ($encrypted.Length -ge 32 -and $encrypted.Length -le 8192) 'CIPHERTEXT_SIZE'
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$salt,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 Need ($plain.Length -ge 2 -and $plain.Length -le 1024 -and ($plain.Length % 2) -eq 0) 'PASSWORD_SIZE'
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
 $secure.MakeReadOnly();[Array]::Clear($plain,0,$plain.Length);$plain=$null
 $cred=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
 $phase='ODATA_GET_ONE_ROW'
 $select=[regex]::Unescape('Ref_Key,LineNumber,\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430,\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430_Type,\u0415\u0434\u0438\u043d\u0438\u0446\u0430\u0418\u0437\u043c\u0435\u0440\u0435\u043d\u0438\u044f,\u0415\u0434\u0438\u043d\u0438\u0446\u0430\u0418\u0437\u043c\u0435\u0440\u0435\u043d\u0438\u044f_Type,\u041a\u043e\u043b\u0438\u0447\u0435\u0441\u0442\u0432\u043e,\u0426\u0435\u043d\u0430,\u0425\u0430\u0440\u0430\u043a\u0442\u0435\u0440\u0438\u0441\u0442\u0438\u043a\u0430_Key,\u0421\u0442\u0430\u0432\u043a\u0430\u041d\u0414\u0421_Key')
 $set=[regex]::Unescape('Document_\u0417\u0430\u043a\u0430\u0437\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044f_\u0417\u0430\u043f\u0430\u0441\u044b')
 $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/'+$set+'?$top=1&$orderby=Ref_Key%20asc,LineNumber%20asc&$select='+[Uri]::EscapeDataString($select)
 $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
 $req.Method='GET';$req.Accept='application/atom+xml';$req.Proxy=$null;$req.AllowAutoRedirect=$false
 $req.PreAuthenticate=$true;$req.Credentials=$cred.GetNetworkCredential()
 $req.Timeout=60000;$req.ReadWriteTimeout=60000
 $response=$req.GetResponse()
 Need ([int]$response.StatusCode -eq 200) 'ODATA_HTTP_NOT200'
 $phase='PARSE_ONE_ROW_LOCAL'
 $sr=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
 try{
  $buffer=New-Object char[] 4096;$data=New-Object Text.StringBuilder;$sz=0
  do{
   $n=$sr.Read($buffer,0,$buffer.Length);$sz+=$n
   Need ($sz -le 4194304) 'FEED_OVER_4M'
   if($n -gt 0){[void]$data.Append($buffer,0,$n)}
  }while($n -gt 0)
 }finally{$sr.Close()}
 $lines=Analyze ($data.ToString())
 $phase='SAVE_AGGREGATE_RECEIPT'
 $out=New-Object Text.StringBuilder
 [void]$out.AppendLine('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';SOURCE=TEST_NEWBASE;ODATA_GET=1;ONEC_WRITES=0;CRM_WRITES=0;RAW_DATA_EXPORTED=0')
 foreach($line in $lines){[void]$out.AppendLine($line)}
 $f=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$bytes=[Text.Encoding]::ASCII.GetBytes($out.ToString());$f.Write($bytes,0,$bytes.Length);$f.Flush()}finally{$f.Close()}
 foreach($line in $lines){Write-Output $line}
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^ONEC_STOCK_ROW_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 $t=$_.Exception.GetType().Name
 if($OfflineFixturePath -eq '' -and $phase -ne 'HOST'){
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';TYPE='+$t),[Text.Encoding]::ASCII)}catch{}
 }
 'RESULT=FAIL;STAGE=ONEC_STOCK_ROW_READONLY_V2;PHASE='+$phase+';GATE='+$gate+';TYPE='+$t
 exit 1
}finally{
 if($null -ne $response){try{$response.Close()}catch{}}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
}

 return (Yes ($Val.Trim() -match $expected))
}
function GuidState([string]$Val){
 $v=$Val.Trim()
 if($v -eq ''){return 'EMPTY'}
 if($v -notmatch '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$'){return 'OTHER'}
 if($v -eq '00000000-0000-0000-0000-000000000000'){return 'ZERO_GUID'}
 return 'NONZERO_GUID'
}
function NumericClass([string]$Val){
 if($Val.Trim() -eq ''){return 'EMPTY'}
 $v=0.0
 if([double]::TryParse($Val,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$v)){
  if($v -gt 0){return 'POSITIVE'}
  if($v -eq 0){return 'ZERO'}
  return 'NEGATIVE'
 }
 return 'NON_NUMERIC'
}
function Analyze([string]$Body){
 $settings=New-Object Xml.XmlReaderSettings
 $settings.ProhibitDtd=$true;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=4194304
 $sr=New-Object IO.StringReader -ArgumentList $Body
 $reader=$null
 try{$reader=[Xml.XmlReader]::Create($sr,$settings);$xml=New-Object Xml.XmlDocument;$xml.XmlResolver=$null;$xml.Load($reader)}
 finally{if($null -ne $reader){$reader.Close()};$sr.Close()}
 Need ($null -eq $xml.DocumentType) 'DOCTYPE_DENIED'
 Need ($xml.DocumentElement.LocalName -eq 'feed') 'NOT_ATOM_FEED'
 $entries=$xml.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']")
 Need ($null -ne $entries -and $entries.Count -le 1) 'TOO_MANY_ENTRIES'
 $lines=New-Object Collections.ArrayList
 [void]$lines.Add('ATOM_ENTRIES='+$entries.Count)
 if($entries.Count -eq 0){
  [void]$lines.Add('ROW_FOUND=NO')
  [void]$lines.Add('RESULT=PARTIAL;STAGE=ONEC_STOCK_ROW_READONLY_V2;GATE=NO_EXISTING_ROWS')
  return ,$lines
 }
 $props=$entries.Item(0).SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
 Need ($null -ne $props) 'ATOM_PROPERTIES_MISSING'
 $nom=Field $props ([regex]::Unescape('\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430'))
 $typ=Field $props ([regex]::Unescape('\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430_Type'))
 $unit=Field $props ([regex]::Unescape('\u0415\u0434\u0438\u043d\u0438\u0446\u0430\u0418\u0437\u043c\u0435\u0440\u0435\u043d\u0438\u044f'))
 $unitType=Field $props ([regex]::Unescape('\u0415\u0434\u0438\u043d\u0438\u0446\u0430\u0418\u0437\u043c\u0435\u0440\u0435\u043d\u0438\u044f_Type'))
 $q=Field $props ([regex]::Unescape('\u041a\u043e\u043b\u0438\u0447\u0435\u0441\u0442\u0432\u043e'))
 $price=Field $props ([regex]::Unescape('\u0426\u0435\u043d\u0430'))
 $ref=Field $props 'Ref_Key'
 $line=Field $props 'LineNumber'
 Need ($nom.Present -and $typ.Present -and $q.Present -and $price.Present -and $ref.Present -and $line.Present) 'EXPECTED_COLUMN_MISSING'
 [void]$lines.Add('ROW_FOUND=YES')
 [void]$lines.Add('REF_KEY_CLASS='+(ShortClass $ref.Value))
 [void]$lines.Add('LINE_NUMBER_CLASS='+(NumericClass $line.Value))
 [void]$lines.Add('NOMENCLATURE_CLASS='+(ShortClass $nom.Value))
 [void]$lines.Add('NOMENCLATURE_TYPE_CLASS='+(ShortClass $typ.Value))
 [void]$lines.Add('NOMENCLATURE_TYPE_PRESENT='+(Yes ($typ.Value.Trim() -ne '')))
 [void]$lines.Add('NOMENCLATURE_TYPE_FAMILY='+(TypeFamily $typ.Value))
 [void]$lines.Add('NOMENCLATURE_TYPE_EXPECTED='+(ExpectedNomenclature $typ.Value))
 [void]$lines.Add('UNIT_CLASS='+(ShortClass $unit.Value))
 [void]$lines.Add('UNIT_TYPE_CLASS='+(ShortClass $unitType.Value))
 [void]$lines.Add('UNIT_TYPE_FAMILY='+(TypeFamily $unitType.Value))
 [void]$lines.Add('QTY_CLASS='+(NumericClass $q.Value))
 [void]$lines.Add('PRICE_CLASS='+(NumericClass $price.Value))
 $characteristic=Field $props ([regex]::Unescape('\u0425\u0430\u0440\u0430\u043a\u0442\u0435\u0440\u0438\u0441\u0442\u0438\u043a\u0430_Key'))
 [void]$lines.Add('CHARACTERISTIC_PRESENT='+(Yes ($characteristic.Value.Trim() -ne '')))
 [void]$lines.Add('CHARACTERISTIC_GUID_STATE='+(GuidState $characteristic.Value))
 $vat=Field $props ([regex]::Unescape('\u0421\u0442\u0430\u0432\u043a\u0430\u041d\u0414\u0421_Key'))
 [void]$lines.Add('VAT_RATE_PRESENT='+(Yes ($vat.Value.Trim() -ne '')))
 [void]$lines.Add('VAT_RATE_GUID_STATE='+(GuidState $vat.Value))
 [void]$lines.Add('RESULT=PASS;STAGE=ONEC_STOCK_ROW_READONLY_V2')
 return ,$lines
}
try{
 if($OfflineFixturePath -ne ''){
  Need ($env:CI -eq 'true') 'OFFLINE_CI_ONLY'
  Need ([IO.File]::Exists($OfflineFixturePath)) 'OFFLINE_FIXTURE_MISSING'
  foreach($line in (Analyze ([IO.File]::ReadAllText($OfflineFixturePath,[Text.Encoding]::UTF8)))){Write-Output $line}
  exit 0
 }
 Need ($env:COMPUTERNAME -eq 'SRV' -and $ExpectedComputerName -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_REQUIRED'
 Need ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-19') 'LOCAL_SERVICE_ONLY'
 $cfg=Join-Path $root 'config\collector.ini';$secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 Need ([IO.File]::Exists($cfg) -and [IO.File]::Exists($secret)) 'MACHINE_CONFIG_MISSING'
 Need (-not [IO.File]::Exists($status)) 'ALREADY_RUN'
 $flags=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
 foreach($key in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  Need ($flags -match ('(?m)^'+[regex]::Escape($key)+'\r?$')) 'LEGACY_FLAGS_CHANGED'
 }
 $phase='AUTH_LOCAL'
 Add-Type -AssemblyName System.Security
 $salt=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
 $encrypted=[IO.File]::ReadAllBytes($secret)
 Need ($encrypted.Length -ge 32 -and $encrypted.Length -le 8192) 'CIPHERTEXT_SIZE'
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$salt,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 Need ($plain.Length -ge 2 -and $plain.Length -le 1024 -and ($plain.Length % 2) -eq 0) 'PASSWORD_SIZE'
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
 $secure.MakeReadOnly();[Array]::Clear($plain,0,$plain.Length);$plain=$null
 $cred=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
 $phase='ODATA_GET_ONE_ROW'
 $select=[regex]::Unescape('Ref_Key,LineNumber,\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430,\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430_Type,\u0415\u0434\u0438\u043d\u0438\u0446\u0430\u0418\u0437\u043c\u0435\u0440\u0435\u043d\u0438\u044f,\u0415\u0434\u0438\u043d\u0438\u0446\u0430\u0418\u0437\u043c\u0435\u0440\u0435\u043d\u0438\u044f_Type,\u041a\u043e\u043b\u0438\u0447\u0435\u0441\u0442\u0432\u043e,\u0426\u0435\u043d\u0430,\u0425\u0430\u0440\u0430\u043a\u0442\u0435\u0440\u0438\u0441\u0442\u0438\u043a\u0430_Key,\u0421\u0442\u0430\u0432\u043a\u0430\u041d\u0414\u0421_Key')
 $set=[regex]::Unescape('Document_\u0417\u0430\u043a\u0430\u0437\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044f_\u0417\u0430\u043f\u0430\u0441\u044b')
 $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/'+$set+'?$top=1&$orderby=Ref_Key%20asc,LineNumber%20asc&$select='+[Uri]::EscapeDataString($select)
 $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
 $req.Method='GET';$req.Accept='application/atom+xml';$req.Proxy=$null;$req.AllowAutoRedirect=$false
 $req.PreAuthenticate=$true;$req.Credentials=$cred.GetNetworkCredential()
 $req.Timeout=60000;$req.ReadWriteTimeout=60000
 $response=$req.GetResponse()
 Need ([int]$response.StatusCode -eq 200) 'ODATA_HTTP_NOT200'
 $phase='PARSE_ONE_ROW_LOCAL'
 $sr=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
 try{
  $buffer=New-Object char[] 4096;$data=New-Object Text.StringBuilder;$sz=0
  do{
   $n=$sr.Read($buffer,0,$buffer.Length);$sz+=$n
   Need ($sz -le 4194304) 'FEED_OVER_4M'
   if($n -gt 0){[void]$data.Append($buffer,0,$n)}
  }while($n -gt 0)
 }finally{$sr.Close()}
 $lines=Analyze ($data.ToString())
 $phase='SAVE_AGGREGATE_RECEIPT'
 $out=New-Object Text.StringBuilder
 [void]$out.AppendLine('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';SOURCE=TEST_NEWBASE;ODATA_GET=1;ONEC_WRITES=0;CRM_WRITES=0;RAW_DATA_EXPORTED=0')
 foreach($line in $lines){[void]$out.AppendLine($line)}
 $f=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$bytes=[Text.Encoding]::ASCII.GetBytes($out.ToString());$f.Write($bytes,0,$bytes.Length);$f.Flush()}finally{$f.Close()}
 foreach($line in $lines){Write-Output $line}
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^ONEC_STOCK_ROW_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 $t=$_.Exception.GetType().Name
 if($OfflineFixturePath -eq '' -and $phase -ne 'HOST'){
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';TYPE='+$t),[Text.Encoding]::ASCII)}catch{}
 }
 'RESULT=FAIL;STAGE=ONEC_STOCK_ROW_READONLY_V2;PHASE='+$phase+';GATE='+$gate+';TYPE='+$t
 exit 1
}finally{
 if($null -ne $response){try{$response.Close()}catch{}}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
}

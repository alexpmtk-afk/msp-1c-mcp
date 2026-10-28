#requires -version 2
# One bounded local OData GET on TEST NewBase: one NON-DELETED Customer Order HEADER at most.
# No personal names, GUIDs, order numbers or raw financial values leave SRV.
param([string]$ExpectedComputerName='SRV',[string]$OfflineFixturePath='')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\bitrix-to-onec-order-header-readonly-v2.txt'
$phase='HOST';$plain=$null;$response=$null
function Fail([string]$Code){throw ('ONEC_ORDER_HEADER_'+$Code)}
function Need([bool]$ok,[string]$Code){if(-not $ok){Fail $Code}}
function Field($Props,[string]$Name){
 $node=$Props.SelectSingleNode("./*[local-name()='"+$Name+"']")
 if($null -eq $node){return @{Present=$false;Value=''}}
 return @{Present=$true;Value=[string]$node.InnerText}
}
function Presence([string]$Val){
 if($Val.Trim() -eq ''){return 'EMPTY'}
 return 'NONEMPTY'
}
function GuidState([string]$Val){
 $v=$Val.Trim()
 if($v -eq ''){return 'EMPTY'}
 if($v -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'){return 'OTHER'}
 if($v -eq '00000000-0000-0000-0000-000000000000'){return 'ZERO_GUID'}
 return 'NONZERO_GUID'
}
function BoolState([string]$Val){
 $v=$Val.Trim().ToLowerInvariant()
 if($v -eq 'true' -or $v -eq '1'){return 'TRUE'}
 if($v -eq 'false' -or $v -eq '0'){return 'FALSE'}
 if($v -eq ''){return 'EMPTY'}
 return 'OTHER'
}
function TechnicalShape([string]$Val){
 $v=$Val.Trim()
 if($v -eq ''){return 'EMPTY'}
 if($v -match '(^|\.)Enum_[\p{L}\p{N}_]+(\.[\p{L}\p{N}_]+)?$'){return 'ENUM'}
 if($v -match '(^|\.)Catalog_[\p{L}\p{N}_]+$'){return 'CATALOG'}
 if($v -match '(^|\.)Document_[\p{L}\p{N}_]+$'){return 'DOCUMENT'}
 return 'OTHER'
}
function NumericClass([string]$Val){
 if($Val.Trim() -eq ''){return 'EMPTY'}
 $d=0.0
 if([double]::TryParse($Val,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d)){
  if($d -gt 0){return 'POSITIVE'}
  if($d -eq 0){return 'ZERO'}
  return 'NEGATIVE'
 }
 return 'OTHER'
}
function Analyze([string]$Body){
 $settings=New-Object Xml.XmlReaderSettings
 $settings.ProhibitDtd=$true;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=4194304
 $sr=New-Object IO.StringReader -ArgumentList $Body
 $reader=$null
 try{$reader=[Xml.XmlReader]::Create($sr,$settings);$doc=New-Object Xml.XmlDocument;$doc.XmlResolver=$null;$doc.Load($reader)}
 finally{if($null -ne $reader){$reader.Close()};$sr.Close()}
 Need ($null -eq $doc.DocumentType) 'DOCTYPE_DENIED'
 Need ($doc.DocumentElement.LocalName -eq 'feed') 'NOT_ATOM_FEED'
 $entries=$doc.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']")
 Need ($null -ne $entries -and $entries.Count -le 1) 'TOO_MANY_ENTRIES'
 $lines=New-Object Collections.ArrayList
 [void]$lines.Add('ATOM_ENTRIES='+$entries.Count)
 if($entries.Count -eq 0){
  [void]$lines.Add('ROW_FOUND=NO')
  [void]$lines.Add('RESULT=PARTIAL;STAGE=ONEC_ORDER_HEADER_READONLY_V2;GATE=NO_EXISTING_ORDERS')
  return ,$lines
 }
 $props=$entries.Item(0).SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
 Need ($null -ne $props) 'HEADER_PROPERTIES_MISSING'
 Need ((BoolState ((Field $props 'DeletionMark').Value)) -eq 'FALSE') 'MARKED_FOR_DELETION'
 $ref=Field $props 'Ref_Key'
 $num=Field $props 'Number'
 Need ($ref.Present -and $num.Present) 'HEADER_ID_FIELDS_MISSING'
 [void]$lines.Add('ROW_FOUND=YES')
 [void]$lines.Add('ORDER_GUID_STATE='+(GuidState $ref.Value))
 [void]$lines.Add('ORDER_NUMBER_PRESENT='+(Presence $num.Value))
 [void]$lines.Add('BUYER_GUID_STATE='+(GuidState ((Field $props ([regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442_Key'))).Value)))
 [void]$lines.Add('ORGANIZATION_GUID_STATE='+(GuidState ((Field $props ([regex]::Unescape('\u041e\u0440\u0433\u0430\u043d\u0438\u0437\u0430\u0446\u0438\u044f_Key'))).Value)))
 [void]$lines.Add('CONTRACT_GUID_STATE='+(GuidState ((Field $props ([regex]::Unescape('\u0414\u043e\u0433\u043e\u0432\u043e\u0440_Key'))).Value)))
 [void]$lines.Add('CURRENCY_GUID_STATE='+(GuidState ((Field $props ([regex]::Unescape('\u0412\u0430\u043b\u044e\u0442\u0430\u0414\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u0430_Key'))).Value)))
 [void]$lines.Add('PRICE_TYPE_GUID_STATE='+(GuidState ((Field $props ([regex]::Unescape('\u0412\u0438\u0434\u0426\u0435\u043d_Key'))).Value)))
 [void]$lines.Add('ORDER_KIND_SHAPE='+(TechnicalShape ((Field $props ([regex]::Unescape('\u0412\u0438\u0434\u0417\u0430\u043a\u0430\u0437\u0430'))).Value)))
 [void]$lines.Add('OPERATION_KIND_SHAPE='+(TechnicalShape ((Field $props ([regex]::Unescape('\u0412\u0438\u0434\u041e\u043f\u0435\u0440\u0430\u0446\u0438\u0438'))).Value)))
 [void]$lines.Add('ORDER_STATUS_SHAPE='+(TechnicalShape ((Field $props ([regex]::Unescape('\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435\u0417\u0430\u043a\u0430\u0437\u0430'))).Value)))
 [void]$lines.Add('VAT_MODE_SHAPE='+(TechnicalShape ((Field $props ([regex]::Unescape('\u041d\u0430\u043b\u043e\u0433\u043e\u043e\u0431\u043b\u043e\u0436\u0435\u043d\u0438\u0435\u041d\u0414\u0421'))).Value)))
 [void]$lines.Add('POSTED_FLAG='+(BoolState ((Field $props ([regex]::Unescape('Posted'))).Value)))
 [void]$lines.Add('DELETION_FLAG='+(BoolState ((Field $props ([regex]::Unescape('DeletionMark'))).Value)))
 [void]$lines.Add('VAT_INCLUDED_FLAG='+(BoolState ((Field $props ([regex]::Unescape('\u0421\u0443\u043c\u043c\u0430\u0412\u043a\u043b\u044e\u0447\u0430\u0435\u0442\u041d\u0414\u0421'))).Value)))
 [void]$lines.Add('VAT_COST_FLAG='+(BoolState ((Field $props ([regex]::Unescape('\u041d\u0414\u0421\u0412\u043a\u043b\u044e\u0447\u0430\u0442\u044c\u0412\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c'))).Value)))
 [void]$lines.Add('DATE_PRESENT='+(Presence ((Field $props ([regex]::Unescape('Date'))).Value)))
 [void]$lines.Add('TOTAL_CLASS='+(NumericClass ((Field $props ([regex]::Unescape('\u0421\u0443\u043c\u043c\u0430\u0414\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u0430'))).Value)))
 [void]$lines.Add('RESULT=PASS;STAGE=ONEC_ORDER_HEADER_READONLY_V2')
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
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
 $cipher=[IO.File]::ReadAllBytes($secret)
 Need ($cipher.Length -ge 32 -and $cipher.Length -le 8192) 'CIPHERTEXT_SIZE'
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 Need ($plain.Length -ge 2 -and $plain.Length -le 1024 -and ($plain.Length % 2) -eq 0) 'PASSWORD_SIZE'
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
 $secure.MakeReadOnly();[Array]::Clear($plain,0,$plain.Length);$plain=$null
 $cred=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
 $phase='ODATA_GET_ONE_HEADER'
 $set=[regex]::Unescape('Document_\u0417\u0430\u043a\u0430\u0437\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044f')
 $fields=[regex]::Unescape('Ref_Key,Number,Date,Posted,DeletionMark,\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442_Key,\u041e\u0440\u0433\u0430\u043d\u0438\u0437\u0430\u0446\u0438\u044f_Key,\u0414\u043e\u0433\u043e\u0432\u043e\u0440_Key,\u0412\u0430\u043b\u044e\u0442\u0430\u0414\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u0430_Key,\u0412\u0438\u0434\u0426\u0435\u043d_Key,\u0412\u0438\u0434\u0417\u0430\u043a\u0430\u0437\u0430,\u0412\u0438\u0434\u041e\u043f\u0435\u0440\u0430\u0446\u0438\u0438,\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435\u0417\u0430\u043a\u0430\u0437\u0430,\u041d\u0430\u043b\u043e\u0433\u043e\u043e\u0431\u043b\u043e\u0436\u0435\u043d\u0438\u0435\u041d\u0414\u0421,\u0421\u0443\u043c\u043c\u0430\u0412\u043a\u043b\u044e\u0447\u0430\u0435\u0442\u041d\u0414\u0421,\u041d\u0414\u0421\u0412\u043a\u043b\u044e\u0447\u0430\u0442\u044c\u0412\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c,\u0421\u0443\u043c\u043c\u0430\u0414\u043e\u043a\u0443\u043c\u0435\u043d\u0442\u0430')
 $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/'+$set+'?$top=1&$filter=DeletionMark%20eq%20false&$select='+[Uri]::EscapeDataString($fields)
 $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
 $req.Method='GET';$req.Accept='application/atom+xml';$req.Proxy=$null;$req.AllowAutoRedirect=$false
 $req.PreAuthenticate=$true;$req.Credentials=$cred.GetNetworkCredential()
 $req.Timeout=60000;$req.ReadWriteTimeout=60000
 $response=$req.GetResponse()
 Need ([int]$response.StatusCode -eq 200) 'ODATA_HTTP_NOT200'
 $phase='PARSE_ONE_HEADER_LOCAL'
 $r=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
 try{
  $buf=New-Object char[] 4096;$data=New-Object Text.StringBuilder;$count=0
  do{$n=$r.Read($buf,0,$buf.Length);$count+=$n;Need ($count -le 4194304) 'FEED_OVER_4M';if($n -gt 0){[void]$data.Append($buf,0,$n)}}while($n -gt 0)
 }finally{$r.Close()}
 $summary=Analyze ($data.ToString())
 $phase='SAVE_REDACTED_RECEIPT'
 $out=New-Object Text.StringBuilder
 [void]$out.AppendLine('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';SOURCE=TEST_NEWBASE;ODATA_GET=1;ONEC_WRITES=0;CRM_WRITES=0;RAW_DATA_EXPORTED=0')
 foreach($line in $summary){[void]$out.AppendLine($line)}
 $f=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$bytes=[Text.Encoding]::ASCII.GetBytes($out.ToString());$f.Write($bytes,0,$bytes.Length);$f.Flush()}finally{$f.Close()}
 foreach($line in $summary){Write-Output $line}
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^ONEC_ORDER_HEADER_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 $t=$_.Exception.GetType().Name
 if($OfflineFixturePath -eq '' -and $phase -ne 'HOST'){
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate+';TYPE='+$t),[Text.Encoding]::ASCII)}catch{}
 }
 'RESULT=FAIL;STAGE=ONEC_ORDER_HEADER_READONLY_V2;PHASE='+$phase+';GATE='+$gate+';TYPE='+$t
 exit 1
}finally{
 if($null -ne $response){try{$response.Close()}catch{}}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
}

#requires -version 2
# TEST NewBase full read-only 1C OData contact-info coverage for exactly 6433 active buyers.
# No 1C/CRM writes, no customer data/phones/GUIDs leave physical SRV.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\customer-phone-coverage-readonly-v1.txt'
$phase='PRECHECK';$resp=$null;$plain=$null;$encrypted=$null;$secure=$null
function Fail([string]$Code){throw ('PHONE_COVER_'+$Code)}
function U([string]$Encoded){return [regex]::Unescape($Encoded)}
function Field($Props,[string]$Name){
 $n=$Props.SelectSingleNode("./*[local-name()='"+$Name+"']")
 if($null -eq $n){Fail 'FIELD_MISSING'}
 if($n.InnerText.Length -gt 4096){Fail 'FIELD_TOO_LARGE'}
 return [string]$n.InnerText
}
function GetBody([string]$Uri,[string]$Mime,[int]$Max){
 $resp=$null
 try{
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($Uri)
  $req.Method='GET';$req.Accept=$Mime
  $req.Proxy=$null;$req.AllowAutoRedirect=$false
  $req.Credentials=$script:credential.GetNetworkCredential();$req.PreAuthenticate=$true
  $req.Timeout=30000;$req.ReadWriteTimeout=30000
  $resp=$req.GetResponse()
  if([int]$resp.StatusCode -ne 200){Fail 'HTTP_NOT_200'}
  $reader=New-Object System.IO.StreamReader -ArgumentList @($resp.GetResponseStream(),[Text.Encoding]::UTF8)
  try{
   $buffer=New-Object char[] 8192
   $body=New-Object Text.StringBuilder;$size=0
   do{$n=$reader.Read($buffer,0,$buffer.Length);$size+=$n;if($size -gt $Max){Fail 'BODY_TOO_LARGE'};if($n -gt 0){[void]$body.Append($buffer,0,$n)}}while($n -gt 0)
   return $body.ToString()
  }finally{$reader.Close()}
 }finally{if($null -ne $resp){$resp.Close()}}
}
function Count(){
 $raw=GetBody ($script:base+'/$count') 'text/plain' 128
 $n=$raw.Trim()
 if($n -notmatch '^[0-9]{1,7}$'){Fail 'ODATA_COUNT_NOT_INTEGER'}
 return [int]$n
}
function ReadPage([int]$Skip,[int]$Top,[string]$Fields){
 $url=$script:base+'?$select='+[Uri]::EscapeDataString($Fields)+'&$orderby='+[Uri]::EscapeDataString('Ref_Key asc,LineNumber asc')+'&$top='+$Top+'&$skip='+$Skip
 $raw=GetBody $url 'application/atom+xml' 3145728
 $settings=New-Object System.Xml.XmlReaderSettings
 $settings.ProhibitDtd=$true;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=3145728
 $input=New-Object System.IO.StringReader -ArgumentList $raw
 $reader=$null
 try{
  $reader=[System.Xml.XmlReader]::Create($input,$settings)
  $xml=New-Object System.Xml.XmlDocument;$xml.XmlResolver=$null;$xml.Load($reader)
 }finally{if($null -ne $reader){$reader.Close()};$input.Close()}
 if($xml.DocumentElement.LocalName -ne 'feed'){Fail 'SOURCE_NOT_ATOM_FEED'}
 return @($xml.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']"))
}
try{
 if($env:COMPUTERNAME -ne 'SRV' -or $ExpectedComputerName -ne 'SRV'){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 if([IO.File]::Exists($status)){Fail 'RECEIPT_ALREADY_EXISTS'}
 $meta=Join-Path $root 'state\customer-phone-contactinfo-metadata-v3.txt'
 $db=Join-Path $root 'data\customers.db'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 $cfg=Join-Path $root 'config\collector.ini'
 foreach($p in @($meta,$db,$sqlite,$secret,$cfg)){
  if(-not [IO.File]::Exists($p)){Fail 'MACHINE_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DENIED'}
 }
 $m=[IO.File]::ReadAllText($meta,[Text.Encoding]::ASCII)
 if($m -notmatch '^UTC=[^;]+;STATUS=PASS;SOURCE=TEST_NEWBASE;ENTITY_SETS=1492;CONTACTINFO_SET=YES;ORIGIN=PART_ENTITY_SET;'){Fail 'METADATA_NOT_ACCEPTED'}
 foreach($field in @('Ref_Key','LineNumber','\u041d\u043e\u043c\u0435\u0440\u0422\u0435\u043b\u0435\u0444\u043e\u043d\u0430','\u041d\u043e\u043c\u0435\u0440\u0422\u0435\u043b\u0435\u0444\u043e\u043d\u0430\u0411\u0435\u0437\u041a\u043e\u0434\u043e\u0432')){
  $needle=if($field -match '^\\u'){('FIELD='+$field+';')}else{('FIELD='+$field+';')}
  if($m.IndexOf($needle,[StringComparison]::Ordinal) -lt 0){Fail 'METADATA_PHONE_FIELD_MISSING'}
 }
 $flags=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
 foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  if($flags -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'COLLECTOR_NOT_SAFE_IDLE'}
 }
 $phase='LOCAL_BUYER_MAP'
 $query="SELECT onec_guid FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0 ORDER BY onec_guid;"
 $rawBuyers=@(& $sqlite -readonly -batch -bail $db $query 2>$null)
 if($LASTEXITCODE -ne 0 -or $rawBuyers.Count -ne 6433){Fail 'ACTIVE_SOURCE_NOT_6433'}
 $buyers=@{}
 foreach($g in $rawBuyers){
  $g=([string]$g).Trim().ToLowerInvariant()
  if($g -notmatch '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$' -or $buyers.ContainsKey($g)){Fail 'BUYER_GUID_INVALID'}
  $buyers[$g]=$true
 }
 $phase='SERVICE_DPAPI'
 Add-Type -AssemblyName System.Security
 $encrypted=[IO.File]::ReadAllBytes($secret)
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1'),[Security.Cryptography.DataProtectionScope]::LocalMachine)
 if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'SECRET_SIZE_INVALID'}
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
 $secure.MakeReadOnly();[Array]::Clear($plain,0,$plain.Length);$plain=$null
 $script:credential=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
 $owner=U '\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b'
 $part=U '\u041a\u043e\u043d\u0442\u0430\u043a\u0442\u043d\u0430\u044f\u0418\u043d\u0444\u043e\u0440\u043c\u0430\u0446\u0438\u044f'
 $pPhone=U '\u041d\u043e\u043c\u0435\u0440\u0422\u0435\u043b\u0435\u0444\u043e\u043d\u0430'
 $pRaw=U '\u041d\u043e\u043c\u0435\u0440\u0422\u0435\u043b\u0435\u0444\u043e\u043d\u0430\u0411\u0435\u0437\u041a\u043e\u0434\u043e\u0432'
 $pType=U '\u0422\u0438\u043f'
 $pPresent=U '\u041f\u0440\u0435\u0434\u0441\u0442\u0430\u0432\u043b\u0435\u043d\u0438\u0435'
 $script:base='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$owner+'_'+$part
 $phase='CONTACT_COUNT_BEFORE'
 $expected=Count
 if($expected -lt 1 -or $expected -gt 200000){Fail 'CONTACT_ROW_COUNT_OUT_OF_BOUNDS'}
 $phase='CONTACT_PAGE_SCAN'
 $fields='Ref_Key,LineNumber,'+$pType+','+$pPhone+','+$pRaw+','+$pPresent
 $seen=@{};$phones=@{};$rows=0;$pageCount=0;$matched=0;$outside=0
 $withPhone=0;$withRaw=0;$withDisplay=0;$candidateRows=0;$phoneTypeRows=0
 while($rows -lt $expected){
  if($pageCount -ge 2000){Fail 'PAGE_LIMIT'}
  $items=@(ReadPage $rows 100 $fields)
  if($items.Count -lt 1 -or $items.Count -gt 100 -or ($rows+$items.Count) -gt $expected){Fail 'PAGE_COUNT_INVALID'}
  foreach($entry in $items){
   $props=$entry.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
   if($null -eq $props){Fail 'PROPERTIES_MISSING'}
   $g=(Field $props 'Ref_Key').Trim().ToLowerInvariant()
   $line=(Field $props 'LineNumber').Trim()
   if($g -notmatch '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$' -or $line -notmatch '^[1-9][0-9]{0,8}$'){Fail 'CONTACT_KEY_INVALID'}
   $key=$g+':'+$line
   if($seen.ContainsKey($key)){Fail 'PAGING_DUPLICATE_KEY'}
   $seen[$key]=$true
   $number=(Field $props $pPhone).Trim()
   $rawNumber=(Field $props $pRaw).Trim()
   $display=(Field $props $pPresent).Trim()
   $type=(Field $props $pType).Trim()
   if($buyers.ContainsKey($g)){
    $matched++
    if($number.Length -gt 0){$withPhone++}
    if($rawNumber.Length -gt 0){$withRaw++}
    if($display.Length -gt 0){$withDisplay++}
    if($type.IndexOf((U '\u0422\u0435\u043b\u0435\u0444\u043e\u043d'),[StringComparison]::OrdinalIgnoreCase) -ge 0){$phoneTypeRows++}
    if($number.Length -gt 0 -or $rawNumber.Length -gt 0){
     $candidateRows++
     if($phones.ContainsKey($g)){$phones[$g]++}else{$phones[$g]=1}
    }
   }else{$outside++}
  }
  $rows+=$items.Count;$pageCount++
 }
 $phase='CONTACT_COUNT_AFTER'
 if((Count) -ne $expected -or $seen.Count -ne $expected){Fail 'COUNT_CHANGED_DURING_SCAN'}
 $multiple=0
 foreach($n in $phones.Values){if($n -gt 1){$multiple++}}
 $result='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+
 ';STATUS=PASS;SOURCE=TEST_NEWBASE;ACTIVE_BUYERS=6433;CONTACT_ROWS='+$expected+
 ';MATCHED_BUYER_ROWS='+$matched+';OTHER_ROWS='+$outside+
 ';PHONE_NUMBER_ROWS='+$withPhone+';PHONE_WITHOUT_CODES_ROWS='+$withRaw+
 ';DISPLAY_ROWS='+$withDisplay+';PHONE_TYPE_ROWS='+$phoneTypeRows+
 ';PHONE_CANDIDATE_ROWS='+$candidateRows+';BUYERS_WITH_PHONE='+$phones.Count+
 ';BUYERS_MULTIPLE_PHONES='+$multiple+';PAGES='+$pageCount+
 ';ONEC_WRITES=0;CRM_WRITES=0;DB_WRITES=0;PII_EXPORTED=0'
 [IO.File]::WriteAllText($status,$result,[Text.Encoding]::ASCII)
 $result
 'RESULT=PASS;STAGE=TEST_NEWBASE_PHONE_COVERAGE_READONLY_V1'
}catch [Net.WebException]{
 $code='NETWORK'
 if($null -ne $_.Exception.Response){$code='HTTP_'+[int]$_.Exception.Response.StatusCode}
 'RESULT=FAIL;STAGE=PHONE_COVERAGE_V1;GATE='+$code+';PHASE='+$phase
 exit 1
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^PHONE_COVER_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 $exception=$_.Exception.GetType().Name
 if($exception -notmatch '^[A-Za-z0-9_]{1,70}$'){$exception='UNKNOWN'}
 'RESULT=FAIL;STAGE=PHONE_COVERAGE_V1;GATE='+$gate+';PHASE='+$phase+';EXCEPTION_TYPE='+$exception
 exit 1
}finally{
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
 if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
 if($null -ne $secure){$secure.Dispose()}
}
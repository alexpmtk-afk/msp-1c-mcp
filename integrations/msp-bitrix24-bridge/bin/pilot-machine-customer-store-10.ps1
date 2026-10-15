#requires -version 2
# Machine-owned LOCAL SERVICE 10-buyer pilot from TEST 1C into SQLite.
# Only aggregated output; no outbound buyer records or 1C modifications.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\customer-pilot10-status.txt'
$response=$null
$encrypted=$null
$plain=$null
$secure=$null
function Fail([string]$Code){throw ('PILOT_'+$Code)}
function Col($Node,[string]$Name){
  $item=$Node.SelectSingleNode("./*[local-name()='"+$Name+"']")
  if($null -eq $item){Fail 'SOURCE_FIELD_MISSING'}
  if($item.InnerText.Length -gt 4096){Fail 'FIELD_TOO_LONG'}
  return $item.InnerText
}
function Literal([string]$Value){
  if($null -eq $Value){return 'NULL'}
  $data=[Text.Encoding]::UTF8.GetBytes($Value)
  if($data.Length -gt 16384){Fail 'TEXT_BYTES_TOO_LONG'}
  if($data.Length -eq 0){return "''"}
  return ("CAST(X'"+[BitConverter]::ToString($data).Replace('-','')+"' AS TEXT)")
}
function Sql([string]$Executable,[string]$Database,[string]$Query){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$Executable
  $psi.Arguments='-batch -bail "'+$Database+'"'
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardInput=$true
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $process=New-Object Diagnostics.Process
  $process.StartInfo=$psi
  try{
    if(-not $process.Start()){Fail 'SQLITE_START_FAILED'}
    $process.StandardInput.Write($Query)
    $process.StandardInput.Close()
    $result=$process.StandardOutput.ReadToEnd()
    $errors=$process.StandardError.ReadToEnd()
    if(-not $process.WaitForExit(20000)){$process.Kill();Fail 'SQLITE_TIMEOUT'}
    if($process.ExitCode -ne 0 -or $errors.Trim().Length -gt 0){Fail 'SQLITE_COMMAND_FAILED'}
    return $result.Trim()
  }finally{$process.Close()}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'NOT_LOCAL_SERVICE'}
  $exe=Join-Path $root 'bin\sqlite3.exe'
  $db=Join-Path $root 'data\customers.db'
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $conf=Join-Path $root 'config\collector.ini'
  foreach($file in @($exe,$db,$secret,$conf)){
    if(-not [IO.File]::Exists($file)){Fail 'MACHINE_FILE_MISSING'}
    if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  }
  if([IO.File]::Exists($status)){Fail 'PILOT_STATUS_ALREADY_EXISTS'}
  $config=[IO.File]::ReadAllText($conf,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($config -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'NOT_SAFE_IDLE'}
  }
  if((Sql $exe $db 'SELECT count(*) FROM customers;') -ne '0'){Fail 'DB_NOT_EMPTY'}
  if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY_FAILED'}
  $phase='DECRYPT'
  Add-Type -AssemblyName System.Security
  $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
  $encrypted=[IO.File]::ReadAllBytes($secret)
  if($encrypted.Length -lt 32 -or $encrypted.Length -gt 8192){Fail 'SECRET_SIZE_INVALID'}
  $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'PASSWORD_SIZE_INVALID'}
  $secure=New-Object Security.SecureString
  for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
  $secure.MakeReadOnly()
  [Array]::Clear($plain,0,$plain.Length)
  $plain=$null
  $credential=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
  $table=[regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')
  $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
  $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
  $full=[regex]::Unescape('\u041d\u0430\u0438\u043c\u0435\u043d\u043e\u0432\u0430\u043d\u0438\u0435\u041f\u043e\u043b\u043d\u043e\u0435')
  $inn=[regex]::Unescape('\u0418\u041d\u041d')
  $type=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u0424\u0438\u0437\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $fio=[regex]::Unescape('\u0424\u0418\u041e')
  $legal=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $person=[regex]::Unescape('\u0424\u0438\u0437\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $filter=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
  $select='Ref_Key,Description,'+$full+','+$inn+','+$type+','+$fio
  $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$table+
    '?$filter='+[Uri]::EscapeDataString($filter)+
    '&$select='+[Uri]::EscapeDataString($select)+
    '&$orderby=Ref_Key%20asc&$top=10'
  $phase='SOURCE_GET'
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET'
  $req.Accept='application/atom+xml'
  $req.Proxy=$null
  $req.AllowAutoRedirect=$false
  $req.PreAuthenticate=$true
  $req.Credentials=$credential.GetNetworkCredential()
  $req.Timeout=20000
  $req.ReadWriteTimeout=20000
  $response=$req.GetResponse()
  if([int]$response.StatusCode -ne 200){Fail 'SOURCE_HTTP_NOT_200'}
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
  try{
    $buf=New-Object char[] 8192
    $sb=New-Object Text.StringBuilder
    $read=0
    do{
      $n=$reader.Read($buf,0,$buf.Length)
      $read+=$n
      if($read -gt 2097152){Fail 'SOURCE_RESPONSE_TOO_LARGE'}
      if($n -gt 0){[void]$sb.Append($buf,0,$n)}
    }while($n -gt 0)
  }finally{$reader.Close()}
  $phase='VALIDATE_ALL_TEN'
  $xml=New-Object Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.LoadXml($sb.ToString())
  if($xml.DocumentElement.LocalName -ne 'feed'){Fail 'SOURCE_NOT_ATOM'}
  $entries=@($xml.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']"))
  if($entries.Count -ne 10){Fail 'SOURCE_TEN_ROWS_REQUIRED'}
  $seen=@{}
  $legalCount=0
  $personCount=0
  $reviewCount=0
  $fullCount=0
  $innCount=0
  $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  $sql=New-Object Text.StringBuilder
  [void]$sql.Append('BEGIN IMMEDIATE;'+[Environment]::NewLine)
  foreach($entry in $entries){
    $props=$entry.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
    if($null -eq $props){Fail 'SOURCE_PROPERTIES_MISSING'}
    $guid=([string](Col $props 'Ref_Key')).Trim().ToLowerInvariant()
    if($guid -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){Fail 'SOURCE_GUID_INVALID'}
    if($seen.ContainsKey($guid)){Fail 'SOURCE_GUID_DUPLICATE'}
    $seen[$guid]=$true
    $short=[string](Col $props 'Description')
    $long=[string](Col $props $full)
    $tax=[string](Col $props $inn)
    $kind=[string](Col $props $type)
    $personName=[string](Col $props $fio)
    if($kind -eq $legal){$category='LEGAL';$legalCount++}
    elseif($kind -eq $person){$category='PERSON';$personCount++}
    else{$category='REVIEW';$reviewCount++}
    if($long.Trim().Length -gt 0){$fullCount++}
    if($tax.Trim().Length -gt 0){$innCount++}
    $taxSql='NULL'
    if($tax.Trim().Length -gt 0){$taxSql=Literal $tax}
    $insert="INSERT INTO customers(onec_guid,onec_type,name_short,name_full,person_name,inn,buyer,deletion_mark,invalid,source_version,updated_at_utc,needs_review) VALUES ('"+
      $guid+"','"+$category+"',"+(Literal $short)+","+(Literal $long)+","+(Literal $personName)+","+
      $taxSql+",1,0,0,NULL,'"+$stamp+"',"+([int]($category -eq 'REVIEW'))+");"
    [void]$sql.Append($insert+[Environment]::NewLine)
  }
  [void]$sql.Append('COMMIT;'+[Environment]::NewLine)
  if($seen.Count -ne 10 -or ($legalCount+$personCount+$reviewCount) -ne 10){Fail 'SOURCE_COUNTS_INCONSISTENT'}
  $phase='SQLITE_COMMIT_TEN'
  $null=Sql $exe $db $sql.ToString()
  $phase='BACKREAD'
  $check=Sql $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) || ':' || sum(CASE WHEN buyer=1 AND deletion_mark=0 AND invalid=0 THEN 1 ELSE 0 END) FROM customers;"
  if($check -ne '10:10:10'){Fail 'BACKREAD_COUNT_MISMATCH'}
  if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKREAD_INTEGRITY_FAILED'}
  $line='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;IDENTITY=LOCAL_SERVICE;ROWS=10;UNIQUE_GUIDS=10;DB_INTEGRITY=ok;ONEC_WRITES=0;BITRIX_CALLS=0'
  [IO.File]::WriteAllText($status,$line,[Text.Encoding]::ASCII)
  'PILOT_ROWS=10'
  'PILOT_UNIQUE_GUIDS=10'
  'PILOT_LEGAL='+$legalCount
  'PILOT_PERSON='+$personCount
  'PILOT_REVIEW='+$reviewCount
  'PILOT_FULL_NAME_NONBLANK='+$fullCount
  'PILOT_INN_NONBLANK='+$innCount
  'SQLITE_BACKREAD=PASS'
  'DB_INTEGRITY=ok'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_PILOT10'
}catch [Net.WebException]{
  $gate='ODATA_TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_PILOT10;GATE='+$gate+';PHASE='+$phase
  exit 1
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^PILOT_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_PILOT10;GATE='+$gate+';PHASE='+$phase
  exit 1
}finally{
  if($null -ne $response){$response.Close()}
  if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
  if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
  if($null -ne $secure){$secure.Dispose()}
}

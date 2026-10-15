#requires -version 2
# One-time full initial buyer load: 1C TEST -> LOCAL SQLite, LOCAL SERVICE only.
# Atom OData GET, bounded pages, all-or-nothing SQLite transaction.
# Buyer names, GUIDs, INN and request payloads never leave physical SRV.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\customer-initial-load-status.txt'
$response=$null
$encrypted=$null
$plain=$null
$secure=$null
function Fail([string]$Code){throw ('FULL_'+$Code)}
function Field($Node,[string]$Name){
  $x=$Node.SelectSingleNode("./*[local-name()='"+$Name+"']")
  if($null -eq $x){Fail 'SOURCE_FIELD_MISSING'}
  if($x.InnerText.Length -gt 4096){Fail 'SOURCE_FIELD_TOO_LARGE'}
  return $x.InnerText
}
function Literal([string]$Value){
  if($null -eq $Value){return 'NULL'}
  $bytes=[Text.Encoding]::UTF8.GetBytes($Value)
  if($bytes.Length -gt 16384){Fail 'SOURCE_FIELD_BYTES_TOO_LARGE'}
  if($bytes.Length -eq 0){return "''"}
  return ("CAST(X'"+[BitConverter]::ToString($bytes).Replace('-','')+"' AS TEXT)")
}
function Sql([string]$Executable,[string]$Database,[string]$Text){
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$Executable
  $psi.Arguments='-batch -bail "'+$Database+'"'
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardInput=$true
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $p=New-Object Diagnostics.Process
  $p.StartInfo=$psi
  try{
    if(-not $p.Start()){Fail 'SQLITE_PROCESS_START_FAILED'}
    $p.StandardInput.Write($Text)
    $p.StandardInput.Close()
    $out=$p.StandardOutput.ReadToEnd()
    $err=$p.StandardError.ReadToEnd()
    if(-not $p.WaitForExit(120000)){$p.Kill();Fail 'SQLITE_PROCESS_TIMEOUT'}
    if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0){Fail 'SQLITE_TRANSACTION_REJECTED'}
    if($out.Length -gt 1024){Fail 'SQLITE_OUTPUT_TOO_LARGE'}
    return $out.Trim()
  }finally{$p.Close()}
}
function Request([string]$Uri){
  $r=[Net.HttpWebRequest][Net.WebRequest]::Create($Uri)
  $r.Method='GET'
  $r.Accept='application/atom+xml'
  $r.Proxy=$null
  $r.AllowAutoRedirect=$false
  $r.Credentials=$script:credential.GetNetworkCredential()
  $r.PreAuthenticate=$true
  $r.Timeout=30000
  $r.ReadWriteTimeout=30000
  return $r
}
function Count([string]$Filter){
  $r=$null
  try{
    $uri=$script:base+'/$count?$filter='+[Uri]::EscapeDataString($Filter)
    $r=(Request $uri).GetResponse()
    if([int]$r.StatusCode -ne 200){Fail 'COUNT_HTTP_NOT_200'}
    $reader=New-Object IO.StreamReader -ArgumentList @($r.GetResponseStream(),[Text.Encoding]::ASCII)
    try{
      $buf=New-Object char[] 64
      $length=$reader.Read($buf,0,$buf.Length)
      if($length -lt 1 -or $length -gt 20){Fail 'COUNT_LENGTH_INVALID'}
      $text=(New-Object String -ArgumentList @($buf,0,$length)).Trim()
      if($text -notmatch '^[0-9]{1,8}$'){Fail 'COUNT_NOT_INTEGER'}
      return [int]::Parse($text)
    }finally{$reader.Close()}
  }finally{if($null -ne $r){$r.Close()}}
}
function Page([string]$Filter,[int]$Skip,[int]$Take,[string]$Fields){
  $r=$null
  try{
    $uri=$script:base+'?$filter='+[Uri]::EscapeDataString($Filter)+
      '&$select='+[Uri]::EscapeDataString($Fields)+
      '&$orderby=Ref_Key%20asc&$top='+$Take+'&$skip='+$Skip
    $r=(Request $uri).GetResponse()
    if([int]$r.StatusCode -ne 200){Fail 'PAGE_HTTP_NOT_200'}
    $reader=New-Object IO.StreamReader -ArgumentList @($r.GetResponseStream(),[Text.Encoding]::UTF8)
    try{
      $buffer=New-Object char[] 8192
      $data=New-Object Text.StringBuilder
      $size=0
      do{
        $n=$reader.Read($buffer,0,$buffer.Length)
        $size+=$n
        if($size -gt 3145728){Fail 'PAGE_TOO_LARGE'}
        if($n -gt 0){[void]$data.Append($buffer,0,$n)}
      }while($n -gt 0)
    }finally{$reader.Close()}
    $xml=New-Object Xml.XmlDocument
    $xml.XmlResolver=$null
    $xml.LoadXml($data.ToString())
    if($xml.DocumentElement.LocalName -ne 'feed'){Fail 'NOT_ATOM_FEED'}
    return @($xml.SelectNodes("/*[local-name()='feed']/*[local-name()='entry']"))
  }finally{if($null -ne $r){$r.Close()}}
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'NOT_LOCAL_SERVICE'}
  $exe=Join-Path $root 'bin\sqlite3.exe'
  $db=Join-Path $root 'data\customers.db'
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $conf=Join-Path $root 'config\collector.ini'
  $pilotStatus=Join-Path $root 'state\customer-pilot10-status.txt'
  foreach($file in @($exe,$db,$secret,$conf,$pilotStatus)){
    if(-not [IO.File]::Exists($file)){Fail 'MACHINE_FILE_MISSING'}
    if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_FILE'}
  }
  if([IO.File]::Exists($status)){Fail 'INITIAL_STATUS_ALREADY_EXISTS'}
  $cfg=[IO.File]::ReadAllText($conf,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($cfg -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'COLLECTOR_NOT_SAFE_IDLE'}
  }
  $proof=[IO.File]::ReadAllText($pilotStatus,[Text.Encoding]::ASCII).Trim()
  if($proof -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;ROWS=10;UNIQUE_GUIDS=10;DB_INTEGRITY=ok;ONEC_WRITES=0;BITRIX_CALLS=0$'){Fail 'PILOT_PROOF_NOT_PASS'}
  if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DATABASE_INTEGRITY_INVALID'}
  $existing=@((Sql $exe $db 'SELECT onec_guid FROM customers ORDER BY onec_guid;').Split([char]10))
  $current=@{}
  foreach($id in $existing){
    $g=$id.Trim().ToLowerInvariant()
    if($g.Length -eq 0){continue}
    if($g -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){Fail 'PILOT_GUID_INVALID'}
    if($current.ContainsKey($g)){Fail 'PILOT_DUPLICATE_GUID'}
    $current[$g]=$true
  }
  if($current.Count -ne 10){Fail 'EXPECTED_TEN_PRIOR_CUSTOMERS'}
  if((Sql $exe $db 'SELECT count(*) FROM scan_runs;') -ne '0'){Fail 'PREVIOUS_SCAN_RUN_EXISTS'}
  $phase='DECRYPT'
  Add-Type -AssemblyName System.Security
  $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
  $encrypted=[IO.File]::ReadAllBytes($secret)
  if($encrypted.Length -lt 32 -or $encrypted.Length -gt 8192){Fail 'CIPHERTEXT_SIZE_INVALID'}
  $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'PASSWORD_LENGTH_INVALID'}
  $secure=New-Object Security.SecureString
  for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
  $secure.MakeReadOnly()
  [Array]::Clear($plain,0,$plain.Length)
  $plain=$null
  $script:credential=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
  $table=[regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')
  $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
  $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
  $full=[regex]::Unescape('\u041d\u0430\u0438\u043c\u0435\u043d\u043e\u0432\u0430\u043d\u0438\u0435\u041f\u043e\u043b\u043d\u043e\u0435')
  $inn=[regex]::Unescape('\u0418\u041d\u041d')
  $typ=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u0424\u0438\u0437\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $fio=[regex]::Unescape('\u0424\u0418\u041e')
  $legal=[regex]::Unescape('\u042e\u0440\u0438\u0434\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $person=[regex]::Unescape('\u0424\u0438\u0437\u0438\u0447\u0435\u0441\u043a\u043e\u0435\u041b\u0438\u0446\u043e')
  $filter=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
  $fields='Ref_Key,Description,'+$full+','+$inn+','+$typ+','+$fio
  $script:base='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$table
  $phase='COUNT_BEFORE'
  $expected=Count $filter
  if($expected -ne 6433){Fail 'SOURCE_COUNT_CHANGED'}
  $phase='PAGED_SOURCE_READ'
  $sql=New-Object Text.StringBuilder
  [void]$sql.Append('BEGIN IMMEDIATE;'+[Environment]::NewLine)
  $seen=@{}
  $fetched=0
  $pages=0
  $legalCount=0
  $personCount=0
  $reviewCount=0
  $namesCount=0
  $innCount=0
  $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  while($fetched -lt $expected){
    if($pages -ge 150){Fail 'PAGE_LIMIT_EXCEEDED'}
    $batch=@(Page $filter $fetched 100 $fields)
    $n=$batch.Count
    if($n -lt 1 -or $n -gt 100 -or ($fetched+$n) -gt $expected){Fail 'PAGE_SIZE_INVALID'}
    foreach($entry in $batch){
      $props=$entry.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
      if($null -eq $props){Fail 'PROPERTIES_MISSING'}
      $g=([string](Field $props 'Ref_Key')).Trim().ToLowerInvariant()
      if($g -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){Fail 'GUID_INVALID'}
      if($seen.ContainsKey($g)){Fail 'DUPLICATE_SOURCE_GUID'}
      $seen[$g]=$true
      $short=[string](Field $props 'Description')
      $long=[string](Field $props $full)
      $tax=[string](Field $props $inn)
      $categoryRaw=[string](Field $props $typ)
      $personName=[string](Field $props $fio)
      if($categoryRaw -eq $legal){$category='LEGAL';$legalCount++}
      elseif($categoryRaw -eq $person){$category='PERSON';$personCount++}
      else{$category='REVIEW';$reviewCount++}
      if($long.Trim().Length -gt 0){$namesCount++}
      if($tax.Trim().Length -gt 0){$innCount++}
      $taxExpr='NULL'
      if($tax.Trim().Length -gt 0){$taxExpr=Literal $tax}
      $q="INSERT INTO customers(onec_guid,onec_type,name_short,name_full,person_name,inn,buyer,deletion_mark,invalid,source_version,updated_at_utc,needs_review) VALUES ('"+
         $g+"','"+$category+"',"+(Literal $short)+","+(Literal $long)+","+(Literal $personName)+","+
         $taxExpr+",1,0,0,NULL,'"+$stamp+"',"+([int]($category -eq 'REVIEW'))+") "+
         "ON CONFLICT(onec_guid) DO UPDATE SET onec_type=excluded.onec_type,name_short=excluded.name_short,"+
         "name_full=excluded.name_full,person_name=excluded.person_name,inn=excluded.inn,"+
         "buyer=excluded.buyer,deletion_mark=excluded.deletion_mark,invalid=excluded.invalid,"+
         "source_version=excluded.source_version,updated_at_utc=excluded.updated_at_utc,needs_review=excluded.needs_review;"
      [void]$sql.Append($q+[Environment]::NewLine)
      if($sql.Length -gt 25165824){Fail 'TRANSACTION_TOO_LARGE'}
    }
    $fetched+=$n
    $pages++
  }
  if($fetched -ne 6433 -or $seen.Count -ne 6433){Fail 'SOURCE_ROWS_NOT_UNIQUE_6433'}
  if(($legalCount+$personCount+$reviewCount) -ne 6433){Fail 'SOURCE_TYPE_TOTAL_MISMATCH'}
  foreach($guid in $current.Keys){if(-not $seen.ContainsKey($guid)){Fail 'PILOT_GUID_DISAPPEARED'}}
  $phase='COUNT_AFTER'
  if((Count $filter) -ne 6433){Fail 'SOURCE_COUNT_CHANGED_DURING_SCAN'}
  $run='initial-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')
  $phase='TRANSACTION_COMMIT'
  [void]$sql.Append("INSERT INTO scan_runs(run_id,phase,status,expected_count,read_count,unique_count,start_utc,finish_utc,failure_code) VALUES ('"+
    $run+"','INITIAL','COMPLETE',6433,6433,6433,'"+$stamp+"','"+
    [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+"',NULL);"+[Environment]::NewLine)
  [void]$sql.Append("CREATE TEMP TABLE accept_count (n INTEGER NOT NULL CHECK(n=6433));"+[Environment]::NewLine)
  [void]$sql.Append("INSERT INTO accept_count SELECT count(*) FROM customers;"+[Environment]::NewLine)
  [void]$sql.Append("CREATE TEMP TABLE accept_active (n INTEGER NOT NULL CHECK(n=6433));"+[Environment]::NewLine)
  [void]$sql.Append("INSERT INTO accept_active SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;"+[Environment]::NewLine)
  [void]$sql.Append('COMMIT;'+[Environment]::NewLine)
  $null=Sql $exe $db $sql.ToString()
  $phase='BACKREAD'
  $aggregate=Sql $exe $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) || ':' || sum(CASE WHEN buyer=1 AND deletion_mark=0 AND invalid=0 THEN 1 ELSE 0 END) FROM customers;"
  if($aggregate -ne '6433:6433:6433'){Fail 'BACKREAD_COUNTS_FAILED'}
  $categories=Sql $exe $db "SELECT sum(CASE WHEN onec_type='LEGAL' THEN 1 ELSE 0 END) || ':' || sum(CASE WHEN onec_type='PERSON' THEN 1 ELSE 0 END) || ':' || sum(CASE WHEN onec_type='REVIEW' THEN 1 ELSE 0 END) FROM customers;"
  if($categories -ne ($legalCount+':'+$personCount+':'+$reviewCount)){Fail 'BACKREAD_CATEGORIES_FAILED'}
  if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKREAD_INTEGRITY_FAILED'}
  if((Sql $exe $db "SELECT count(*) FROM scan_runs WHERE phase='INITIAL' AND status='COMPLETE' AND expected_count=6433 AND read_count=6433 AND unique_count=6433;") -ne '1'){Fail 'BACKREAD_RUN_NOT_COMMITTED'}
  $message='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+
    ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;ROWS=6433;UNIQUE_GUIDS=6433;PAGES='+$pages+
    ';LEGAL='+$legalCount+';PERSON='+$personCount+';REVIEW='+$reviewCount+
    ';DB_INTEGRITY=ok;ONEC_WRITES=0;BITRIX_CALLS=0'
  [IO.File]::WriteAllText($status,$message,[Text.Encoding]::ASCII)
  'SOURCE_COUNT_BEFORE=6433'
  'SOURCE_COUNT_AFTER=6433'
  'SOURCE_ROWS_READ='+$fetched
  'SOURCE_UNIQUE_GUIDS='+$seen.Count
  'SOURCE_PAGES='+$pages
  'DB_ROWS=6433'
  'DB_UNIQUE_GUIDS=6433'
  'DB_LEGAL='+$legalCount
  'DB_PERSON='+$personCount
  'DB_REVIEW='+$reviewCount
  'DB_FULL_NAME_NONBLANK='+$namesCount
  'DB_INN_NONBLANK='+$innCount
  'PILOT_EXISTING_GUIDS_PRESERVED=10'
  'DB_QUICK_CHECK=ok'
  'SCAN_RUN_COMMITTED=YES'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_INITIAL_6433'
}catch [Net.WebException]{
  $gate='ODATA_TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_INITIAL_6433;GATE='+$gate+';PHASE='+$phase
  exit 1
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^FULL_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_STORE_INITIAL_6433;GATE='+$gate+';PHASE='+$phase
  exit 1
}finally{
  if($null -ne $response){$response.Close()}
  if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
  if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
  if($null -ne $secure){$secure.Dispose()}
}

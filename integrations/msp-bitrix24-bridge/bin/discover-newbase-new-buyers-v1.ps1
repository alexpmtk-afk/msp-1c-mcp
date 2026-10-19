#requires -version 2
# Repeatable TEST NewBase scan; only NEW source GUIDs go into an isolated local queue.
# OData GET only; bounded SQLite insert of new buyers; no Bitrix writes.
# Buyer names, GUIDs, INN and request payloads never leave physical SRV.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\msp-newbuyer-discovery-v1.status'
$response=$null
$encrypted=$null
$plain=$null
$secure=$null
function Fail([string]$Code){throw ('DISCOVERY_'+$Code)}
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
$mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspNewbaseSnapshotScanV1')
$hasLock=$false
try{
 if(-not $mutex.WaitOne(0,$false)){Fail 'SOURCE_SCAN_ALREADY_RUNNING'}
 $hasLock=$true
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 foreach($f in @($exe,$db,$secret)){
  if(-not [IO.File]::Exists($f)){Fail 'SOURCE_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_DENIED'}
 }
 if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'SQLITE_INTEGRITY'}
 $map=Sql $exe $db "SELECT count(*)||':'||count(DISTINCT onec_guid)||':'||count(DISTINCT crm_id) FROM msp_initial_map;"
 if($map -ne '6433:6433:6433'){Fail 'BASELINE_MAPPING_INVALID'}
 $prior=Sql $exe $db 'SELECT count(*) FROM customers;'
 if($prior -notmatch '^[0-9]{4,8}
 $phase='SOURCE_AUTH'
 Add-Type -AssemblyName System.Security
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
 $encrypted=[IO.File]::ReadAllBytes($secret)
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'PASSWORD_DECRYPT_UNEXPECTED'}
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
 $secure.MakeReadOnly();[Array]::Clear($plain,0,$plain.Length);$plain=$null
 $script:credential=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
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
 $phase='SOURCE_COUNT_BEFORE'
 $expected=Count $filter
 if($expected -lt 100 -or $expected -gt 200000){Fail 'SOURCE_COUNT_UNEXPECTED'}
 $phase='SOURCE_ALL_PAGES'
 $sql=New-Object Text.StringBuilder
 $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
 [void]$sql.AppendLine('BEGIN IMMEDIATE;')
 [void]$sql.AppendLine('CREATE TEMP TABLE _incoming(onec_guid TEXT PRIMARY KEY,onec_type TEXT,name_short TEXT,name_full TEXT,person_name TEXT,inn TEXT,buyer INTEGER,deletion_mark INTEGER,invalid INTEGER,needs_review INTEGER);')
 $seen=@{};$fetched=0;$pages=0;$legalCount=0;$personCount=0;$reviewCount=0
 while($fetched -lt $expected){
  if($pages -ge 3000){Fail 'PAGE_LIMIT'}
  $batch=@(Page $filter $fetched 100 $fields)
  if($batch.Count -lt 1 -or $batch.Count -gt 100 -or ($fetched+$batch.Count) -gt $expected){Fail 'PAGE_SIZE_CHANGED'}
  foreach($entry in $batch){
   $props=$entry.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
   if($null -eq $props){Fail 'PROPERTIES_MISSING'}
   $g=([string](Field $props 'Ref_Key')).Trim().ToLowerInvariant()
   if($g -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'){Fail 'GUID_INVALID'}
   if($seen.ContainsKey($g)){Fail 'DUPLICATE_GUID'}
   $seen[$g]=$true
   $short=[string](Field $props 'Description');$long=[string](Field $props $full)
   $tax=[string](Field $props $inn);$personName=[string](Field $props $fio)
   $rawType=[string](Field $props $typ)
   if($rawType -eq $legal){$category='LEGAL';$legalCount++}
   elseif($rawType -eq $person){$category='PERSON';$personCount++}
   else{$category='REVIEW';$reviewCount++}
   $query="INSERT INTO _incoming VALUES ('"+$g+"','"+$category+"',"+(Literal $short)+","+(Literal $long)+","+(Literal $personName)+","+(Literal $tax)+",1,0,0,"+([int]($category -eq 'REVIEW'))+");"
   [void]$sql.AppendLine($query)
   if($sql.Length -gt 60000000){Fail 'TRANSACTION_TOO_LARGE'}
  }
  $fetched+=$batch.Count;$pages++
 }
 $phase='SOURCE_COUNT_AFTER'
 if((Count $filter) -ne $expected){Fail 'COUNT_CHANGED_DURING_SCAN'}
 if($seen.Count -ne $expected -or ($legalCount+$personCount+$reviewCount) -ne $expected){Fail 'SCAN_INCOMPLETE'}
 $phase='SOURCE_NEW_GUID_DIFF'
 $backup=Join-Path $root 'data\customers.before-newbuyer-discovery-v1.sqlite.bak'
 if(-not [IO.File]::Exists($backup)){
  $null=Sql $exe $db (".backup '"+($backup.Replace('\','/'))+"'")
 }
 if(-not [IO.File]::Exists($backup) -or (Sql $exe $backup 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKUP_INVALID'}
 $phase='SQLITE_NEW_ONLY_COMMIT'
 [void]$sql.AppendLine('CREATE TEMP TABLE _new AS SELECT i.* FROM _incoming i LEFT JOIN customers c ON c.onec_guid=i.onec_guid WHERE c.onec_guid IS NULL;')
 [void]$sql.AppendLine('CREATE TEMP TABLE _guard(n INTEGER NOT NULL CHECK(n BETWEEN 0 AND 20));')
 [void]$sql.AppendLine('INSERT INTO _guard SELECT count(*) FROM _new;')
 [void]$sql.AppendLine('CREATE TEMP TABLE _map_guard(n INTEGER NOT NULL CHECK(n=0));')
 [void]$sql.AppendLine('INSERT INTO _map_guard SELECT count(*) FROM _new i JOIN msp_initial_map m ON m.onec_guid=i.onec_guid;')
 [void]$sql.AppendLine("CREATE TABLE IF NOT EXISTS msp_newbuyer_queue(onec_guid TEXT PRIMARY KEY,source_type TEXT NOT NULL CHECK(source_type IN ('LEGAL','PERSON','REVIEW')),state TEXT NOT NULL CHECK(state IN ('PENDING','HELD_TYPE','INTENT','DONE','UNCERTAIN')),discovered_utc TEXT NOT NULL,updated_utc TEXT NOT NULL,crm_id INTEGER,entity_kind INTEGER);")
 [void]$sql.AppendLine("INSERT INTO customers(onec_guid,onec_type,name_short,name_full,person_name,inn,buyer,deletion_mark,invalid,source_version,updated_at_utc,needs_review) SELECT onec_guid,onec_type,name_short,name_full,person_name,inn,1,0,0,NULL,'"+$stamp+"',needs_review FROM _new;")
 [void]$sql.AppendLine("INSERT INTO msp_newbuyer_queue(onec_guid,source_type,state,discovered_utc,updated_utc) SELECT onec_guid,onec_type,CASE WHEN onec_type='REVIEW' THEN 'HELD_TYPE' ELSE 'PENDING' END,'"+$stamp+"','"+$stamp+"' FROM _new;")
 [void]$sql.AppendLine("INSERT INTO customer_search_v1(onec_guid,name_short,name_full,person_name,inn) SELECT onec_guid,name_short,name_full,person_name,coalesce(inn,'') FROM _new;")
 [void]$sql.AppendLine('COMMIT;')
 $null=Sql $exe $db $sql.ToString()
 $phase='SQLITE_BACKREAD'
 if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKREAD_INTEGRITY'}
 $sum=Sql $exe $db "SELECT count(*)||':'||coalesce(sum(state='PENDING'),0)||':'||coalesce(sum(state='HELD_TYPE'),0)||':'||coalesce(sum(state='INTENT'),0)||':'||coalesce(sum(state='UNCERTAIN'),0) FROM msp_newbuyer_queue;"
 if($sum -notmatch '^([0-9]+):([0-9]+):([0-9]+):0:0$'){Fail 'QUEUE_STATE_INVALID'}
 $pending=$Matches[2];$held=$Matches[3]
 [IO.File]::WriteAllText($status,('UTC='+$stamp+';STATUS=PASS;SOURCE=TEST_NEWBASE;ROWS='+$expected+';QUEUE='+$sum+';BACKUP=VERIFIED;SQLITE_QUICK_CHECK=OK;ONEC_WRITES=0;CRM_WRITES=0;AUTO_UPDATE=OFF;PII_EXPORTED=0'),[Text.Encoding]::ASCII)
 'SOURCE_ACTIVE_ROWS='+$expected
 'NEWBUYER_QUEUE='+$sum
 'NEWBUYER_PENDING='+$pending
 'NEWBUYER_HELD_TYPE='+$held
 'SQLITE_COMMITTED=PASS'
 'BACKUP=VERIFIED'
 'ONEC_WRITES=0'
 'CRM_WRITES=0'
 'AUTO_UPDATE=OFF'
 'RESULT=PASS;STAGE=MSP_NEWBUYER_DISCOVERY_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^AUTO_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_NEWBUYER_DISCOVERY_V1;GATE='+$gate+';PHASE='+$phase
 'NO_SILENT_PARTIAL_COMMIT=YES'
 'CRM_WRITES=0';'ONEC_WRITES=0';'AUTO_UPDATE=OFF'
 exit 1
}finally{
 if($hasLock){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Dispose()}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
 if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
 if($null -ne $secure){$secure.Dispose()}
}
 -or [int]$prior -lt 6433){Fail 'BASELINE_SOURCE_INVALID'}
 $config=Join-Path $root 'config\collector.ini'
 if(-not [IO.File]::Exists($config)){Fail 'SAFE_IDLE_CONFIG_MISSING'}
 $flags=[IO.File]::ReadAllText($config,[Text.Encoding]::ASCII)
 foreach($f in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){if($flags -notmatch ('(?m)^'+[regex]::Escape($f)+'\s*
 $phase='SOURCE_AUTH'
 Add-Type -AssemblyName System.Security
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
 $encrypted=[IO.File]::ReadAllBytes($secret)
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'PASSWORD_DECRYPT_UNEXPECTED'}
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
 $secure.MakeReadOnly();[Array]::Clear($plain,0,$plain.Length);$plain=$null
 $script:credential=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
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
 $phase='SOURCE_COUNT_BEFORE'
 $expected=Count $filter
 if($expected -lt 100 -or $expected -gt 200000){Fail 'SOURCE_COUNT_UNEXPECTED'}
 $phase='SOURCE_ALL_PAGES'
 $sql=New-Object Text.StringBuilder
 $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
 [void]$sql.AppendLine('BEGIN IMMEDIATE;')
 [void]$sql.AppendLine('CREATE TEMP TABLE _incoming(onec_guid TEXT PRIMARY KEY,onec_type TEXT,name_short TEXT,name_full TEXT,person_name TEXT,inn TEXT,buyer INTEGER,deletion_mark INTEGER,invalid INTEGER,needs_review INTEGER);')
 $seen=@{};$fetched=0;$pages=0;$legalCount=0;$personCount=0;$reviewCount=0
 while($fetched -lt $expected){
  if($pages -ge 3000){Fail 'PAGE_LIMIT'}
  $batch=@(Page $filter $fetched 100 $fields)
  if($batch.Count -lt 1 -or $batch.Count -gt 100 -or ($fetched+$batch.Count) -gt $expected){Fail 'PAGE_SIZE_CHANGED'}
  foreach($entry in $batch){
   $props=$entry.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
   if($null -eq $props){Fail 'PROPERTIES_MISSING'}
   $g=([string](Field $props 'Ref_Key')).Trim().ToLowerInvariant()
   if($g -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'){Fail 'GUID_INVALID'}
   if($seen.ContainsKey($g)){Fail 'DUPLICATE_GUID'}
   $seen[$g]=$true
   $short=[string](Field $props 'Description');$long=[string](Field $props $full)
   $tax=[string](Field $props $inn);$personName=[string](Field $props $fio)
   $rawType=[string](Field $props $typ)
   if($rawType -eq $legal){$category='LEGAL';$legalCount++}
   elseif($rawType -eq $person){$category='PERSON';$personCount++}
   else{$category='REVIEW';$reviewCount++}
   $query="INSERT INTO _incoming VALUES ('"+$g+"','"+$category+"',"+(Literal $short)+","+(Literal $long)+","+(Literal $personName)+","+(Literal $tax)+",1,0,0,"+([int]($category -eq 'REVIEW'))+");"
   [void]$sql.AppendLine($query)
   if($sql.Length -gt 60000000){Fail 'TRANSACTION_TOO_LARGE'}
  }
  $fetched+=$batch.Count;$pages++
 }
 $phase='SOURCE_COUNT_AFTER'
 if((Count $filter) -ne $expected){Fail 'COUNT_CHANGED_DURING_SCAN'}
 if($seen.Count -ne $expected -or ($legalCount+$personCount+$reviewCount) -ne $expected){Fail 'SCAN_INCOMPLETE'}
 $phase='SQLITE_ATOMIC_COMMIT'
 [void]$sql.AppendLine('CREATE TABLE IF NOT EXISTS msp_auto_outbox(onec_guid TEXT PRIMARY KEY,changed_utc TEXT NOT NULL,change_kind TEXT NOT NULL);')
 [void]$sql.AppendLine('CREATE TABLE IF NOT EXISTS msp_auto_scan_runs(id INTEGER PRIMARY KEY,scan_utc TEXT NOT NULL,source_rows INTEGER NOT NULL,new_or_changed INTEGER NOT NULL,missing_buyer INTEGER NOT NULL);')
 $comparison="c.onec_guid IS NULL OR c.onec_type IS NOT i.onec_type OR c.name_short IS NOT i.name_short OR c.name_full IS NOT i.name_full OR c.person_name IS NOT i.person_name OR coalesce(c.inn,'') IS NOT coalesce(i.inn,'') OR c.buyer IS NOT 1 OR c.invalid IS NOT 0 OR c.deletion_mark IS NOT 0 OR c.needs_review IS NOT i.needs_review"
 [void]$sql.AppendLine("INSERT INTO msp_auto_outbox(onec_guid,changed_utc,change_kind) SELECT onec_guid,'"+$stamp+"','UPSERT' FROM _incoming WHERE NOT EXISTS (SELECT 1 FROM msp_auto_scan_runs) AND 1=1 ON CONFLICT(onec_guid) DO NOTHING;")
 [void]$sql.AppendLine("CREATE TEMP TABLE _changed AS SELECT i.onec_guid FROM _incoming i LEFT JOIN customers c ON c.onec_guid=i.onec_guid WHERE "+$comparison+";")
 [void]$sql.AppendLine("CREATE TEMP TABLE _missing AS SELECT c.onec_guid FROM customers c WHERE c.buyer=1 AND NOT EXISTS (SELECT 1 FROM _incoming i WHERE i.onec_guid=c.onec_guid);")
 [void]$sql.AppendLine("INSERT INTO msp_auto_outbox(onec_guid,changed_utc,change_kind) SELECT onec_guid,'"+$stamp+"','UPSERT' FROM _changed WHERE 1=1 ON CONFLICT(onec_guid) DO UPDATE SET changed_utc=excluded.changed_utc,change_kind=excluded.change_kind;")
 [void]$sql.AppendLine("INSERT INTO msp_auto_outbox(onec_guid,changed_utc,change_kind) SELECT onec_guid,'"+$stamp+"','REMOVED' FROM _missing WHERE 1=1 ON CONFLICT(onec_guid) DO UPDATE SET changed_utc=excluded.changed_utc,change_kind=excluded.change_kind;")
 [void]$sql.AppendLine("INSERT INTO customers(onec_guid,onec_type,name_short,name_full,person_name,inn,buyer,deletion_mark,invalid,source_version,updated_at_utc,needs_review) SELECT onec_guid,onec_type,name_short,name_full,person_name,inn,1,0,0,NULL,'"+$stamp+"',needs_review FROM _incoming WHERE 1=1 ON CONFLICT(onec_guid) DO UPDATE SET onec_type=excluded.onec_type,name_short=excluded.name_short,name_full=excluded.name_full,person_name=excluded.person_name,inn=excluded.inn,buyer=1,deletion_mark=0,invalid=0,updated_at_utc=excluded.updated_at_utc,needs_review=excluded.needs_review WHERE customers.onec_type IS NOT excluded.onec_type OR customers.name_short IS NOT excluded.name_short OR customers.name_full IS NOT excluded.name_full OR customers.person_name IS NOT excluded.person_name OR coalesce(customers.inn,'') IS NOT coalesce(excluded.inn,'') OR customers.buyer IS NOT 1 OR customers.invalid IS NOT 0 OR customers.deletion_mark IS NOT 0 OR customers.needs_review IS NOT excluded.needs_review;")
 [void]$sql.AppendLine("UPDATE customers SET buyer=0,updated_at_utc='"+$stamp+"' WHERE onec_guid IN (SELECT onec_guid FROM _missing);")
 [void]$sql.AppendLine('DELETE FROM customer_search_v1;')
 [void]$sql.AppendLine("INSERT INTO customer_search_v1(onec_guid,name_short,name_full,person_name,inn) SELECT onec_guid,name_short,name_full,person_name,coalesce(inn,'') FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;")
 [void]$sql.AppendLine("INSERT INTO msp_auto_scan_runs(scan_utc,source_rows,new_or_changed,missing_buyer) SELECT '"+$stamp+"',"+$expected+",(SELECT count(*) FROM _changed),(SELECT count(*) FROM _missing);")
 [void]$sql.AppendLine('CREATE TEMP TABLE _check(n INTEGER NOT NULL CHECK(n='+$expected+'));')
 [void]$sql.AppendLine('INSERT INTO _check SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;')
 [void]$sql.AppendLine('COMMIT;')
 $null=Sql $exe $db $sql.ToString()
 if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKREAD_INTEGRITY'}
 $aggregate=Sql $exe $db "SELECT source_rows||':'||new_or_changed||':'||missing_buyer FROM msp_auto_scan_runs ORDER BY id DESC LIMIT 1;"
 if($aggregate -match '^([0-9]+):([0-9]+):([0-9]+)$'){$changed=$Matches[2];$removed=$Matches[3]}else{Fail 'BACKREAD_RUN_INVALID'}
 [IO.File]::WriteAllText($status,('UTC='+$stamp+';STATUS=PASS;SOURCE=TEST_NEWBASE;ROWS='+$expected+';CHANGED='+$changed+';REMOVED='+$removed),[Text.Encoding]::ASCII)
 'TEST_NEWBASE_ROWS='+$expected
 'SOURCE_CHANGED_OR_NEW='+$changed
 'NO_LONGER_ACTIVE_BUYERS='+$removed
 'BITRIX_OUTBOX_PERSISTENT=YES'
 'SQLITE_ATOMIC_COMMIT=PASS'
 'NEWBASE_WRITES=NO'
 'RESULT=PASS;STAGE=MSP_NEWBASE_SOURCE_REFRESH'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^AUTO_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_NEWBASE_SOURCE_REFRESH;GATE='+$gate+';PHASE='+$phase
 'NO_SILENT_PARTIAL_COMMIT=YES'
 exit 1
}finally{
 if($hasLock){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Dispose()}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
 if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
 if($null -ne $secure){$secure.Dispose()}
}
)){Fail 'NOT_SAFE_IDLE'}}
 $phase='SOURCE_AUTH'
 Add-Type -AssemblyName System.Security
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
 $encrypted=[IO.File]::ReadAllBytes($secret)
 $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'PASSWORD_DECRYPT_UNEXPECTED'}
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
 $secure.MakeReadOnly();[Array]::Clear($plain,0,$plain.Length);$plain=$null
 $script:credential=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
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
 $phase='SOURCE_COUNT_BEFORE'
 $expected=Count $filter
 if($expected -lt 100 -or $expected -gt 200000){Fail 'SOURCE_COUNT_UNEXPECTED'}
 $phase='SOURCE_ALL_PAGES'
 $sql=New-Object Text.StringBuilder
 $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
 [void]$sql.AppendLine('BEGIN IMMEDIATE;')
 [void]$sql.AppendLine('CREATE TEMP TABLE _incoming(onec_guid TEXT PRIMARY KEY,onec_type TEXT,name_short TEXT,name_full TEXT,person_name TEXT,inn TEXT,buyer INTEGER,deletion_mark INTEGER,invalid INTEGER,needs_review INTEGER);')
 $seen=@{};$fetched=0;$pages=0;$legalCount=0;$personCount=0;$reviewCount=0
 while($fetched -lt $expected){
  if($pages -ge 3000){Fail 'PAGE_LIMIT'}
  $batch=@(Page $filter $fetched 100 $fields)
  if($batch.Count -lt 1 -or $batch.Count -gt 100 -or ($fetched+$batch.Count) -gt $expected){Fail 'PAGE_SIZE_CHANGED'}
  foreach($entry in $batch){
   $props=$entry.SelectSingleNode("./*[local-name()='content']/*[local-name()='properties']")
   if($null -eq $props){Fail 'PROPERTIES_MISSING'}
   $g=([string](Field $props 'Ref_Key')).Trim().ToLowerInvariant()
   if($g -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'){Fail 'GUID_INVALID'}
   if($seen.ContainsKey($g)){Fail 'DUPLICATE_GUID'}
   $seen[$g]=$true
   $short=[string](Field $props 'Description');$long=[string](Field $props $full)
   $tax=[string](Field $props $inn);$personName=[string](Field $props $fio)
   $rawType=[string](Field $props $typ)
   if($rawType -eq $legal){$category='LEGAL';$legalCount++}
   elseif($rawType -eq $person){$category='PERSON';$personCount++}
   else{$category='REVIEW';$reviewCount++}
   $query="INSERT INTO _incoming VALUES ('"+$g+"','"+$category+"',"+(Literal $short)+","+(Literal $long)+","+(Literal $personName)+","+(Literal $tax)+",1,0,0,"+([int]($category -eq 'REVIEW'))+");"
   [void]$sql.AppendLine($query)
   if($sql.Length -gt 60000000){Fail 'TRANSACTION_TOO_LARGE'}
  }
  $fetched+=$batch.Count;$pages++
 }
 $phase='SOURCE_COUNT_AFTER'
 if((Count $filter) -ne $expected){Fail 'COUNT_CHANGED_DURING_SCAN'}
 if($seen.Count -ne $expected -or ($legalCount+$personCount+$reviewCount) -ne $expected){Fail 'SCAN_INCOMPLETE'}
 $phase='SQLITE_ATOMIC_COMMIT'
 [void]$sql.AppendLine('CREATE TABLE IF NOT EXISTS msp_auto_outbox(onec_guid TEXT PRIMARY KEY,changed_utc TEXT NOT NULL,change_kind TEXT NOT NULL);')
 [void]$sql.AppendLine('CREATE TABLE IF NOT EXISTS msp_auto_scan_runs(id INTEGER PRIMARY KEY,scan_utc TEXT NOT NULL,source_rows INTEGER NOT NULL,new_or_changed INTEGER NOT NULL,missing_buyer INTEGER NOT NULL);')
 $comparison="c.onec_guid IS NULL OR c.onec_type IS NOT i.onec_type OR c.name_short IS NOT i.name_short OR c.name_full IS NOT i.name_full OR c.person_name IS NOT i.person_name OR coalesce(c.inn,'') IS NOT coalesce(i.inn,'') OR c.buyer IS NOT 1 OR c.invalid IS NOT 0 OR c.deletion_mark IS NOT 0 OR c.needs_review IS NOT i.needs_review"
 [void]$sql.AppendLine("INSERT INTO msp_auto_outbox(onec_guid,changed_utc,change_kind) SELECT onec_guid,'"+$stamp+"','UPSERT' FROM _incoming WHERE NOT EXISTS (SELECT 1 FROM msp_auto_scan_runs) AND 1=1 ON CONFLICT(onec_guid) DO NOTHING;")
 [void]$sql.AppendLine("CREATE TEMP TABLE _changed AS SELECT i.onec_guid FROM _incoming i LEFT JOIN customers c ON c.onec_guid=i.onec_guid WHERE "+$comparison+";")
 [void]$sql.AppendLine("CREATE TEMP TABLE _missing AS SELECT c.onec_guid FROM customers c WHERE c.buyer=1 AND NOT EXISTS (SELECT 1 FROM _incoming i WHERE i.onec_guid=c.onec_guid);")
 [void]$sql.AppendLine("INSERT INTO msp_auto_outbox(onec_guid,changed_utc,change_kind) SELECT onec_guid,'"+$stamp+"','UPSERT' FROM _changed WHERE 1=1 ON CONFLICT(onec_guid) DO UPDATE SET changed_utc=excluded.changed_utc,change_kind=excluded.change_kind;")
 [void]$sql.AppendLine("INSERT INTO msp_auto_outbox(onec_guid,changed_utc,change_kind) SELECT onec_guid,'"+$stamp+"','REMOVED' FROM _missing WHERE 1=1 ON CONFLICT(onec_guid) DO UPDATE SET changed_utc=excluded.changed_utc,change_kind=excluded.change_kind;")
 [void]$sql.AppendLine("INSERT INTO customers(onec_guid,onec_type,name_short,name_full,person_name,inn,buyer,deletion_mark,invalid,source_version,updated_at_utc,needs_review) SELECT onec_guid,onec_type,name_short,name_full,person_name,inn,1,0,0,NULL,'"+$stamp+"',needs_review FROM _incoming WHERE 1=1 ON CONFLICT(onec_guid) DO UPDATE SET onec_type=excluded.onec_type,name_short=excluded.name_short,name_full=excluded.name_full,person_name=excluded.person_name,inn=excluded.inn,buyer=1,deletion_mark=0,invalid=0,updated_at_utc=excluded.updated_at_utc,needs_review=excluded.needs_review WHERE customers.onec_type IS NOT excluded.onec_type OR customers.name_short IS NOT excluded.name_short OR customers.name_full IS NOT excluded.name_full OR customers.person_name IS NOT excluded.person_name OR coalesce(customers.inn,'') IS NOT coalesce(excluded.inn,'') OR customers.buyer IS NOT 1 OR customers.invalid IS NOT 0 OR customers.deletion_mark IS NOT 0 OR customers.needs_review IS NOT excluded.needs_review;")
 [void]$sql.AppendLine("UPDATE customers SET buyer=0,updated_at_utc='"+$stamp+"' WHERE onec_guid IN (SELECT onec_guid FROM _missing);")
 [void]$sql.AppendLine('DELETE FROM customer_search_v1;')
 [void]$sql.AppendLine("INSERT INTO customer_search_v1(onec_guid,name_short,name_full,person_name,inn) SELECT onec_guid,name_short,name_full,person_name,coalesce(inn,'') FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;")
 [void]$sql.AppendLine("INSERT INTO msp_auto_scan_runs(scan_utc,source_rows,new_or_changed,missing_buyer) SELECT '"+$stamp+"',"+$expected+",(SELECT count(*) FROM _changed),(SELECT count(*) FROM _missing);")
 [void]$sql.AppendLine('CREATE TEMP TABLE _check(n INTEGER NOT NULL CHECK(n='+$expected+'));')
 [void]$sql.AppendLine('INSERT INTO _check SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;')
 [void]$sql.AppendLine('COMMIT;')
 $null=Sql $exe $db $sql.ToString()
 if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKREAD_INTEGRITY'}
 $aggregate=Sql $exe $db "SELECT source_rows||':'||new_or_changed||':'||missing_buyer FROM msp_auto_scan_runs ORDER BY id DESC LIMIT 1;"
 if($aggregate -match '^([0-9]+):([0-9]+):([0-9]+)$'){$changed=$Matches[2];$removed=$Matches[3]}else{Fail 'BACKREAD_RUN_INVALID'}
 [IO.File]::WriteAllText($status,('UTC='+$stamp+';STATUS=PASS;SOURCE=TEST_NEWBASE;ROWS='+$expected+';CHANGED='+$changed+';REMOVED='+$removed),[Text.Encoding]::ASCII)
 'TEST_NEWBASE_ROWS='+$expected
 'SOURCE_CHANGED_OR_NEW='+$changed
 'NO_LONGER_ACTIVE_BUYERS='+$removed
 'BITRIX_OUTBOX_PERSISTENT=YES'
 'SQLITE_ATOMIC_COMMIT=PASS'
 'NEWBASE_WRITES=NO'
 'RESULT=PASS;STAGE=MSP_NEWBASE_SOURCE_REFRESH'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^AUTO_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=MSP_NEWBASE_SOURCE_REFRESH;GATE='+$gate+';PHASE='+$phase
 'NO_SILENT_PARTIAL_COMMIT=YES'
 exit 1
}finally{
 if($hasLock){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Dispose()}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
 if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
 if($null -ne $secure){$secure.Dispose()}
}

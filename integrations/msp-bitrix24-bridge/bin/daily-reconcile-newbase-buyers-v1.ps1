#requires -version 2
# Daily 07:45 TEST NewBase full reconcile, SEPARATE from existing new-buyer 30m/5m tasks.
# Low-load contract: max one page GET at a time, 750 ms pacing, no automatic retry, <= 100 rows/page.
# Preview by default; -Apply needs explicit local consent and writes ONLY SRV SQLite.
# Removed 1C buyers become locally inactive. Never delete CRM cards or history.
# Read-only OData GET, atomic local SQLite commit, no customer data in stdout.
# Buyer names, GUIDs, INN and request payloads never leave physical SRV.
param([string]$ExpectedComputerName='SRV',[switch]$Apply)
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\msp-newbase-daily-0745-v1.status'
$response=$null
$encrypted=$null
$plain=$null
$secure=$null
function Fail([string]$Code){throw ('AUTO_'+$Code)}
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
  $r.Timeout=90000
  $r.ReadWriteTimeout=90000
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
 if(-not $mutex.WaitOne(600000,$false)){Fail 'SOURCE_SCAN_BUSY_AFTER_10MIN'}
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
 if($Apply){
  $approval=Join-Path $root 'config\daily-newbase-local-approval.txt'
  if(-not [IO.File]::Exists($approval)){Fail 'LOCAL_APPLY_NOT_APPROVED'}
  if(([IO.File]::GetAttributes($approval) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'APPROVAL_REPARSE'}
  if([IO.File]::ReadAllText($approval,[Text.Encoding]::ASCII).Trim() -ne 'ALLOW_DAILY_LOCAL=YES;SOURCE=TEST_NEWBASE;MAX_REMOVED=5;MAX_NEW=20'){Fail 'APPROVAL_MISMATCH'}
 }
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
  if($fetched -lt $expected){Start-Sleep -Milliseconds 750}
 }
 $phase='SOURCE_COUNT_AFTER'
 Start-Sleep -Milliseconds 750
 if((Count $filter) -ne $expected){Fail 'COUNT_CHANGED_DURING_SCAN'}
 if($seen.Count -ne $expected -or ($legalCount+$personCount+$reviewCount) -ne $expected){Fail 'SCAN_INCOMPLETE'}
 $phase='PREVIEW_DIFF'
 $compare="c.onec_type IS NOT i.onec_type OR c.name_short IS NOT i.name_short OR c.name_full IS NOT i.name_full OR c.person_name IS NOT i.person_name OR coalesce(c.inn,'') IS NOT coalesce(i.inn,'') OR c.buyer IS NOT 1 OR c.deletion_mark IS NOT 0 OR c.invalid IS NOT 0 OR c.needs_review IS NOT i.needs_review"
 [void]$sql.AppendLine('CREATE TEMP TABLE _new AS SELECT i.* FROM _incoming i LEFT JOIN customers c ON c.onec_guid=i.onec_guid WHERE c.onec_guid IS NULL;')
 [void]$sql.AppendLine('CREATE TEMP TABLE _changed AS SELECT i.onec_guid FROM _incoming i JOIN customers c ON c.onec_guid=i.onec_guid WHERE '+$compare+';')
 [void]$sql.AppendLine('CREATE TEMP TABLE _missing AS SELECT c.onec_guid FROM customers c WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND NOT EXISTS(SELECT 1 FROM _incoming i WHERE i.onec_guid=c.onec_guid);')
 $previewScript=$sql.ToString()
 if(-not $previewScript.StartsWith('BEGIN IMMEDIATE;')){Fail 'PREVIEW_TXN_UNEXPECTED'}
 $previewScript='BEGIN;'+$previewScript.Substring('BEGIN IMMEDIATE;'.Length)
 $preview=Sql $exe $db ($previewScript+"SELECT (SELECT count(*) FROM _new)||':'||(SELECT count(*) FROM _changed)||':'||(SELECT count(*) FROM _missing);"+[Environment]::NewLine+'ROLLBACK;')
 if($preview -notmatch '^([0-9]{1,6}):([0-9]{1,6}):([0-9]{1,6})$'){Fail 'PREVIEW_INVALID'}
 $new=[int]$Matches[1];$changed=[int]$Matches[2];$removed=[int]$Matches[3]
 if($new -gt 20){Fail 'TOO_MANY_NEW'}
 if($changed -gt 50){Fail 'TOO_MANY_MODIFIED'}
 if($removed -gt 5 -or $removed -gt [math]::Max(1,[math]::Floor($expected*0.005))){Fail 'TOO_MANY_REMOVED'}
 'TEST_NEWBASE_ACTIVE='+$expected
 'NEW='+$new
 'MODIFIED='+$changed
 'REMOVED_OR_INACTIVE='+$removed
 'ODATA_REQUESTS='+(2+$pages)
 'ODATA_PAGE_SIZE=100;PAGE_PACING_MS=750;RETRIES=0'
 'MODE='+$(if($Apply){'APPLY_LOCAL'}else{'READONLY'})
 if(-not $Apply){
  'SQLITE_WRITES=0';'CRM_WRITES=0';'ONEC_WRITES=0'
  'RESULT=PASS;STAGE=MSP_DAILY_0745_PREVIEW_V1'
  exit 0
 }
 if(($new+$changed+$removed) -eq 0){
  [IO.File]::WriteAllText($status,('UTC='+$stamp+';STATUS=PASS;SOURCE=TEST_NEWBASE;NEW=0;MODIFIED=0;REMOVED=0;LOCAL_WRITES=0;CRM_WRITES=0'),[Text.Encoding]::ASCII)
  'SQLITE_WRITES=0';'CRM_WRITES=0';'ONEC_WRITES=0'
  'RESULT=PASS;STAGE=MSP_DAILY_0745_IDLE_V1'
  exit 0
 }
 $phase='BACKUP'
 $backup=Join-Path $root ('backups\customers.pre-daily-0745-'+[DateTime]::Now.ToString('yyyyMMdd')+'.sqlite.bak')
 if(-not [IO.File]::Exists($backup)){
  $null=Sql $exe $db (".backup '"+($backup.Replace('\','/'))+"'")
 }
 if(-not [IO.File]::Exists($backup) -or (Sql $exe $backup 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKUP_INVALID'}
 $phase='COMMIT_LOCAL'
 [void]$sql.AppendLine("CREATE TABLE IF NOT EXISTS msp_daily_queue(onec_guid TEXT PRIMARY KEY,kind TEXT NOT NULL CHECK(kind IN ('UPDATE','REMOVED')),state TEXT NOT NULL CHECK(state IN ('PENDING','DONE','INTENT','UNCERTAIN','HELD_INACTIVE','HELD_TYPE','HELD_NO_MAP')),source_utc TEXT NOT NULL,crm_id INTEGER,entity_kind INTEGER);")
 [void]$sql.AppendLine("CREATE TEMP TABLE _g1(n INTEGER CHECK(n BETWEEN 0 AND 20));INSERT INTO _g1 SELECT count(*) FROM _new;")
 [void]$sql.AppendLine("CREATE TEMP TABLE _g2(n INTEGER CHECK(n BETWEEN 0 AND 50));INSERT INTO _g2 SELECT count(*) FROM _changed;")
 [void]$sql.AppendLine("CREATE TEMP TABLE _g3(n INTEGER CHECK(n BETWEEN 0 AND 5));INSERT INTO _g3 SELECT count(*) FROM _missing;")
 [void]$sql.AppendLine("CREATE TEMP TABLE _no_prior(n INTEGER CHECK(n=0));INSERT INTO _no_prior SELECT count(*) FROM msp_daily_queue WHERE state IN ('PENDING','INTENT','UNCERTAIN');")
 [void]$sql.AppendLine("CREATE TEMP TABLE _no_pending_new(n INTEGER CHECK(n=0));INSERT INTO _no_pending_new SELECT count(*) FROM msp_newbuyer_queue q JOIN _missing m ON m.onec_guid=q.onec_guid WHERE q.state IN ('PENDING','INTENT','UNCERTAIN');")
 [void]$sql.AppendLine("INSERT INTO customers(onec_guid,onec_type,name_short,name_full,person_name,inn,buyer,deletion_mark,invalid,source_version,updated_at_utc,needs_review) SELECT onec_guid,onec_type,name_short,name_full,person_name,inn,1,0,0,NULL,"+(Literal $stamp)+",needs_review FROM _new;")
 [void]$sql.AppendLine("INSERT INTO msp_newbuyer_queue(onec_guid,source_type,state,discovered_utc,updated_utc) SELECT onec_guid,onec_type,CASE WHEN onec_type='REVIEW' THEN 'HELD_TYPE' ELSE 'PENDING' END,"+(Literal $stamp)+","+(Literal $stamp)+" FROM _new;")
 [void]$sql.AppendLine("UPDATE customers SET onec_type=(SELECT onec_type FROM _incoming WHERE onec_guid=customers.onec_guid),name_short=(SELECT name_short FROM _incoming WHERE onec_guid=customers.onec_guid),name_full=(SELECT name_full FROM _incoming WHERE onec_guid=customers.onec_guid),person_name=(SELECT person_name FROM _incoming WHERE onec_guid=customers.onec_guid),inn=(SELECT inn FROM _incoming WHERE onec_guid=customers.onec_guid),needs_review=(SELECT needs_review FROM _incoming WHERE onec_guid=customers.onec_guid),buyer=1,deletion_mark=0,invalid=0,updated_at_utc="+(Literal $stamp)+" WHERE onec_guid IN (SELECT onec_guid FROM _changed);")
 [void]$sql.AppendLine("UPDATE customers SET buyer=0,updated_at_utc="+(Literal $stamp)+" WHERE onec_guid IN (SELECT onec_guid FROM _missing);")
 [void]$sql.AppendLine("DELETE FROM customer_search_v1 WHERE onec_guid IN (SELECT onec_guid FROM _new UNION SELECT onec_guid FROM _changed UNION SELECT onec_guid FROM _missing);")
 [void]$sql.AppendLine("INSERT INTO customer_search_v1(onec_guid,name_short,name_full,person_name,inn) SELECT c.onec_guid,c.name_short,c.name_full,c.person_name,coalesce(c.inn,'') FROM customers c WHERE c.onec_guid IN (SELECT onec_guid FROM _new UNION SELECT onec_guid FROM _changed) AND c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0;")
 [void]$sql.AppendLine("INSERT INTO msp_daily_queue(onec_guid,kind,state,source_utc,crm_id,entity_kind) SELECT c.onec_guid,'UPDATE',CASE WHEN c.onec_type='REVIEW' OR c.needs_review=1 THEN 'HELD_TYPE' WHEN coalesce((SELECT entity_kind FROM msp_initial_map WHERE onec_guid=c.onec_guid),(SELECT entity_kind FROM msp_auto_map WHERE onec_guid=c.onec_guid),0) NOT IN (3,4) THEN 'HELD_NO_MAP' WHEN coalesce((SELECT entity_kind FROM msp_initial_map WHERE onec_guid=c.onec_guid),(SELECT entity_kind FROM msp_auto_map WHERE onec_guid=c.onec_guid),0) <> CASE WHEN c.onec_type='LEGAL' THEN 4 ELSE 3 END THEN 'HELD_TYPE' ELSE 'PENDING' END,"+(Literal $stamp)+",coalesce((SELECT crm_id FROM msp_initial_map WHERE onec_guid=c.onec_guid),(SELECT crm_id FROM msp_auto_map WHERE onec_guid=c.onec_guid)),coalesce((SELECT entity_kind FROM msp_initial_map WHERE onec_guid=c.onec_guid),(SELECT entity_kind FROM msp_auto_map WHERE onec_guid=c.onec_guid)) FROM customers c JOIN _changed d ON d.onec_guid=c.onec_guid WHERE 1=1 ON CONFLICT(onec_guid) DO UPDATE SET kind=excluded.kind,state=excluded.state,source_utc=excluded.source_utc,crm_id=excluded.crm_id,entity_kind=excluded.entity_kind WHERE msp_daily_queue.state IN ('DONE','HELD_INACTIVE','HELD_NO_MAP','HELD_TYPE');")
 [void]$sql.AppendLine("INSERT INTO msp_daily_queue(onec_guid,kind,state,source_utc,crm_id,entity_kind) SELECT m.onec_guid,'REMOVED','HELD_INACTIVE',"+(Literal $stamp)+",coalesce((SELECT crm_id FROM msp_initial_map WHERE onec_guid=m.onec_guid),(SELECT crm_id FROM msp_auto_map WHERE onec_guid=m.onec_guid)),coalesce((SELECT entity_kind FROM msp_initial_map WHERE onec_guid=m.onec_guid),(SELECT entity_kind FROM msp_auto_map WHERE onec_guid=m.onec_guid)) FROM _missing m WHERE 1=1 ON CONFLICT(onec_guid) DO UPDATE SET kind=excluded.kind,state=excluded.state,source_utc=excluded.source_utc,crm_id=excluded.crm_id,entity_kind=excluded.entity_kind WHERE msp_daily_queue.state IN ('DONE','HELD_INACTIVE','HELD_NO_MAP','HELD_TYPE');")
 [void]$sql.AppendLine('CREATE TEMP TABLE _verify(n INTEGER CHECK(n='+$expected+'));INSERT INTO _verify SELECT count(*) FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;')
 [void]$sql.AppendLine('COMMIT;')
 $null=Sql $exe $db $sql.ToString()
 if((Sql $exe $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'BACKREAD_INTEGRITY'}
 [IO.File]::WriteAllText($status,('UTC='+$stamp+';STATUS=PASS;SOURCE=TEST_NEWBASE;NEW='+$new+';MODIFIED='+$changed+';REMOVED='+$removed+';CRM_WRITES=0'),[Text.Encoding]::ASCII)
 'SQLITE_COMMIT=PASS';'CRM_WRITES=0';'ONEC_WRITES=0'
 'RESULT=PASS;STAGE=MSP_DAILY_0745_LOCAL_V1'
 }catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^AUTO_([A-Z0-9_]+)
 'NO_SILENT_PARTIAL_COMMIT=YES'
 exit 1
}finally{
 if($hasLock){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Dispose()}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
 if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
 if($null -ne $secure){$secure.Dispose()}
}
){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=FAIL;SOURCE=TEST_NEWBASE;PHASE='+$phase+';GATE='+$gate+';CRM_WRITES=0;ONEC_WRITES=0'),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=MSP_DAILY_0745_V1;GATE='+$gate+';PHASE='+$phase
 'NO_SILENT_PARTIAL_COMMIT=YES'
 exit 1
}finally{
 if($hasLock){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Dispose()}
 if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
 if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
 if($null -ne $secure){$secure.Dispose()}
}

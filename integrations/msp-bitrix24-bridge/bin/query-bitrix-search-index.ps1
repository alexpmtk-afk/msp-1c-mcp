#requires -version 2
# Machine-local Bitrix search query adapter: stdout JSON only.
# Must run as LOCAL SERVICE behind a future authenticated HTTPS handler.
# No network listener, HTTP server, credentials or Bitrix writes.
param(
 [string]$ExpectedComputerName='SRV',
 [string]$SearchQuery,
 [ValidateSet('COMPANY','CONTACT')][string]$EntityType='COMPANY',
 [int]$Limit=20,
 [switch]$ReadHexQueryFromStandardInput,
 [switch]$OutputUtf8Hex
)
$ErrorActionPreference='Stop'
function Fail([string]$Code){throw ('QUERY_'+$Code)}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 if($ReadHexQueryFromStandardInput){
   if($null -ne $SearchQuery -and $SearchQuery.Length -gt 0){Fail 'DUAL_INPUT_CHANNEL'}
   $rawHex=[Console]::In.ReadLine()
   if($null -eq $rawHex -or $rawHex.Length -lt 6 -or $rawHex.Length -gt 640 -or ($rawHex.Length % 2) -ne 0 -or $rawHex -notmatch '^[0-9A-Fa-f]+
 $term=$SearchQuery.Trim()
 if($term.Length -lt 3 -or $term.Length -gt 80){Fail 'QUERY_LENGTH_INVALID'}
 if($term -match '[\x00-\x1f\x7f]'){Fail 'QUERY_CONTROLS_FORBIDDEN'}
 if($Limit -lt 1 -or $Limit -gt 20){Fail 'LIMIT_INVALID'}
 $root='C:\ProgramData\MspCustomerStore'
 $db=Join-Path $root 'data\customers.db'
 $exe=Join-Path $root 'bin\sqlite3.exe'
 $receipt=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 if(-not [IO.File]::Exists($db) -or -not [IO.File]::Exists($exe) -or -not [IO.File]::Exists($receipt)){Fail 'LOCAL_INDEX_NOT_READY'}
 if(([IO.File]::GetAttributes($db) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'DB_REPARSE'}
 $mark=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 if($mark -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INDEX_UNACCEPTED'}
 # Quote FTS phrase, then encode as ASCII-safe UTF8 hex SQL literal.
 $phrase='"'+$term.Replace('"','""')+'"'
 $hex=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($phrase)).Replace('-','')
 $kind="c.onec_type IN ('LEGAL','REVIEW')"
 if($EntityType -eq 'CONTACT'){$kind="c.onec_type IN ('PERSON','REVIEW')"}
 $statement="SELECT hex(CAST(json_group_array(json_object("+
  "'id',x.onec_guid,'name',x.name,'sourceType',x.onec_type,'needsReview',x.needs_review)) AS BLOB)) "+
  "FROM (SELECT c.onec_guid,c.onec_type,c.needs_review,"+
  "coalesce(nullif(c.name_short,''),nullif(c.name_full,''),nullif(c.person_name,''),'') AS name "+
  "FROM customer_search_v1 JOIN customers c ON c.onec_guid=customer_search_v1.onec_guid "+
  "WHERE customer_search_v1 MATCH CAST(X'"+$hex+"' AS TEXT) "+
  "AND c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND "+$kind+
  " ORDER BY c.onec_guid LIMIT "+$Limit+") AS x;"
 # The inner LIMIT caps actual result rows before JSON aggregation.
 # User input reaches SQL exclusively via a UTF-8 hex literal.
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$exe
 $psi.Arguments='-readonly -batch -bail "'+$db+'"'
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.RedirectStandardInput=$true
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$psi
 try{
   if(-not $p.Start()){Fail 'SQLITE_START_FAILED'}
   $p.StandardInput.WriteLine($statement)
   $p.StandardInput.Close()
   $text=$p.StandardOutput.ReadToEnd().Trim()
   $err=$p.StandardError.ReadToEnd()
   if(-not $p.WaitForExit(15000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
   if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0){Fail 'SQLITE_SEARCH_FAILED'}
 }finally{$p.Close()}
 if($text.Length -gt 131072 -or ($text.Length % 2) -ne 0){Fail 'RESULT_BYTES_INVALID'}
 if($text -notmatch '^[0-9A-Fa-f]+$'){Fail 'RESULT_NOT_HEX'}
 $bytes=New-Object byte[] ($text.Length/2)
 for($i=0;$i -lt $bytes.Length;$i++){
   $bytes[$i]=[Convert]::ToByte($text.Substring($i*2,2),16)
 }
 $json=[Text.Encoding]::UTF8.GetString($bytes)
 # This is the only output and contains only bounded local query matches.
 if($OutputUtf8Hex){[Console]::Out.WriteLine($text)}else{[Console]::Out.WriteLine($json)}
}catch{
 # Do not output terms, GUIDs, customer labels or SQL statement on failure.
 [Console]::Error.WriteLine('BITRIX_SEARCH_NOT_AVAILABLE')
 exit 1
}
){Fail 'QUERY_HEX_INVALID'}
   $termBytes=New-Object byte[] ($rawHex.Length/2)
   for($i=0;$i -lt $termBytes.Length;$i++){$termBytes[$i]=[Convert]::ToByte($rawHex.Substring($i*2,2),16)}
   $SearchQuery=[Text.Encoding]::UTF8.GetString($termBytes)
 }
 if($null -eq $SearchQuery){Fail 'SEARCH_QUERY_REQUIRED'}
 $term=$SearchQuery.Trim()
 if($term.Length -lt 3 -or $term.Length -gt 80){Fail 'QUERY_LENGTH_INVALID'}
 if($term -match '[\x00-\x1f\x7f]'){Fail 'QUERY_CONTROLS_FORBIDDEN'}
 if($Limit -lt 1 -or $Limit -gt 20){Fail 'LIMIT_INVALID'}
 $root='C:\ProgramData\MspCustomerStore'
 $db=Join-Path $root 'data\customers.db'
 $exe=Join-Path $root 'bin\sqlite3.exe'
 $receipt=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 if(-not [IO.File]::Exists($db) -or -not [IO.File]::Exists($exe) -or -not [IO.File]::Exists($receipt)){Fail 'LOCAL_INDEX_NOT_READY'}
 if(([IO.File]::GetAttributes($db) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'DB_REPARSE'}
 $mark=[IO.File]::ReadAllText($receipt,[Text.Encoding]::ASCII).Trim()
 if($mark -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INDEX_UNACCEPTED'}
 # Quote FTS phrase, then encode as ASCII-safe UTF8 hex SQL literal.
 $phrase='"'+$term.Replace('"','""')+'"'
 $hex=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($phrase)).Replace('-','')
 $kind="c.onec_type IN ('LEGAL','REVIEW')"
 if($EntityType -eq 'CONTACT'){$kind="c.onec_type IN ('PERSON','REVIEW')"}
 $statement="SELECT hex(CAST(json_group_array(json_object("+
  "'id',x.onec_guid,'name',x.name,'sourceType',x.onec_type,'needsReview',x.needs_review)) AS BLOB)) "+
  "FROM (SELECT c.onec_guid,c.onec_type,c.needs_review,"+
  "coalesce(nullif(c.name_short,''),nullif(c.name_full,''),nullif(c.person_name,''),'') AS name "+
  "FROM customer_search_v1 JOIN customers c ON c.onec_guid=customer_search_v1.onec_guid "+
  "WHERE customer_search_v1 MATCH CAST(X'"+$hex+"' AS TEXT) "+
  "AND c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND "+$kind+
  " ORDER BY c.onec_guid LIMIT "+$Limit+") AS x;"
 # The inner LIMIT caps actual result rows before JSON aggregation.
 # User input reaches SQL exclusively via a UTF-8 hex literal.
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$exe
 $psi.Arguments='-readonly -batch -bail "'+$db+'"'
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.RedirectStandardInput=$true
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$psi
 try{
   if(-not $p.Start()){Fail 'SQLITE_START_FAILED'}
   $p.StandardInput.WriteLine($statement)
   $p.StandardInput.Close()
   $text=$p.StandardOutput.ReadToEnd().Trim()
   $err=$p.StandardError.ReadToEnd()
   if(-not $p.WaitForExit(15000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
   if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0){Fail 'SQLITE_SEARCH_FAILED'}
 }finally{$p.Close()}
 if($text.Length -gt 131072 -or ($text.Length % 2) -ne 0){Fail 'RESULT_BYTES_INVALID'}
 if($text -notmatch '^[0-9A-Fa-f]+$'){Fail 'RESULT_NOT_HEX'}
 $bytes=New-Object byte[] ($text.Length/2)
 for($i=0;$i -lt $bytes.Length;$i++){
   $bytes[$i]=[Convert]::ToByte($text.Substring($i*2,2),16)
 }
 $json=[Text.Encoding]::UTF8.GetString($bytes)
 # This is the only output and contains only bounded local query matches.
 [Console]::Out.WriteLine($json)
}catch{
 # Do not output terms, GUIDs, customer labels or SQL statement on failure.
 [Console]::Error.WriteLine('BITRIX_SEARCH_NOT_AVAILABLE')
 exit 1
}

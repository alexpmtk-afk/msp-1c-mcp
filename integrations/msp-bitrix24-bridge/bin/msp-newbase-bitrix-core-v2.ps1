#requires -version 2
# Dot-sourced PS2 library for direct Bitrix24 batch sync from TEST NewBase only.
$ErrorActionPreference='Stop'
function Fail([string]$Code){throw ('NEWBASE_'+$Code)}
function Quote([string]$Value){
 if($Value -match '[\x00-\x1f\x7f]'){Fail 'CONFIG_CONTROLS'}
 return ('"'+$Value.Replace('\','\\').Replace('"','\"')+'"')
}
function JsonQuote([string]$Value){
 $sb=New-Object Text.StringBuilder
 [void]$sb.Append('"')
 foreach($c in $Value.ToCharArray()){
  $n=[int]$c
  if($n -eq 34){[void]$sb.Append('\"')}
  elseif($n -eq 92){[void]$sb.Append('\\')}
  elseif($n -lt 32 -or $n -gt 126){[void]$sb.Append('\u'+$n.ToString('x4'))}
  else{[void]$sb.Append($c)}
 }
 [void]$sb.Append('"')
 return $sb.ToString()
}
function HexUtf8([string]$Value){return ([BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($Value))).Replace('-','')}
function Unhex([string]$Value){
 if(($Value.Length % 2) -ne 0 -or $Value -notmatch '^[A-F0-9]*$' -or $Value.Length -gt 1024){Fail 'HEX_INVALID'}
 $bytes=New-Object byte[] ($Value.Length/2)
 for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=[Convert]::ToByte($Value.Substring($i*2,2),16)}
 return [Text.Encoding]::UTF8.GetString($bytes)
}
function SqlJson([string]$Json,[string]$Select){
 if($Json.Length -gt 4194304){Fail 'JSON_TOO_LARGE'}
 $cmd="WITH j(doc) AS (SELECT CAST(X'"+(HexUtf8 $Json)+"' AS TEXT)) "+$Select
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $script:root 'bin\sqlite3.exe'
 $i.Arguments='-batch -bail ":memory:"'
 $i.UseShellExecute=$false
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $i.CreateNoWindow=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'SQLITE_START'}
  $p.StandardInput.WriteLine($cmd);$p.StandardInput.Close()
  $result=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(10000)){$p.Kill();Fail 'SQLITE_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $result.Length -gt 1024){Fail 'SQLITE_PARSE'}
  return $result
 }finally{$p.Close()}
}
function Http([string]$Method,[string]$Body){
 if(@('batch','crm.item.get','crm.requisite.list','crm.requisite.get') -notcontains $Method){Fail 'UNAPPROVED_METHOD'}
 if($Body.Length -gt 64000 -or $Body -match '[^\x20-\x7e]'){Fail 'BODY_NOT_ASCII'}
 $cfg='url = '+(Quote ($script:base+$Method+'.json'))+[Environment]::NewLine
 $cfg+='request = "POST"'+[Environment]::NewLine
 $cfg+='header = "Content-Type: application/json"'+[Environment]::NewLine
 $cfg+='header = "Accept: application/json"'+[Environment]::NewLine
 $cfg+='data-binary = '+(Quote $Body)+[Environment]::NewLine
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $script:root 'bin\curl.exe'
 $ca=Join-Path $script:root 'config\curl-ca-bundle.crt'
 $i.Arguments='-q --silent --show-error --noproxy "*" --proto "=https" --tlsv1.2 --tls-max 1.2 --cacert "'+$ca+'" --max-redirs 0 --connect-timeout 10 --max-time 25 --write-out "__MSP_HTTP__:%{http_code}" --config -'
 $i.UseShellExecute=$false
 $i.RedirectStandardInput=$true
 $i.RedirectStandardOutput=$true
 $i.RedirectStandardError=$true
 $i.CreateNoWindow=$true
 $p=New-Object Diagnostics.Process
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'CURL_START'}
  $p.StandardInput.Write($cfg);$p.StandardInput.Close();$cfg=$null
  $utf8=New-Object IO.StreamReader -ArgumentList @($p.StandardOutput.BaseStream,[Text.Encoding]::UTF8,$true)
  $out=$utf8.ReadToEnd()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'CURL_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $out.Length -gt 4194304){Fail 'CURL_FAILED'}
  $at=$out.LastIndexOf('__MSP_HTTP__:')
  if($at -lt 0 -or $out.Substring($at+13) -notmatch '^[0-9]{3}$'){Fail 'HTTP_STATUS_INVALID'}
  $code=[int]$out.Substring($at+13)
  if($code -ne 200){Fail ('HTTP_'+$code)}
  return $out.Substring(0,$at)
 }finally{$p.Close()}
}

function Url([string]$Value){return [Uri]::EscapeDataString($Value)}
function Query([string]$Sql){
 $db=Join-Path $script:root 'data\customers.db'
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $script:root 'bin\sqlite3.exe'
 $i.Arguments='-batch -bail "'+$db+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true
 $i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'LOCAL_DB_START'}
  $p.StandardInput.WriteLine($Sql);$p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd().Trim()
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'LOCAL_DB_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0 -or $out.Length -gt 131072){Fail 'LOCAL_DB_ERROR'}
  return $out
 }finally{$p.Close()}
}
function Lit([string]$Value){
 $h=HexUtf8 $Value
 if($h.Length -gt 32768){Fail 'SQL_VALUE_TOO_LONG'}
 return "CAST(X'"+$h+"' AS TEXT)"
}
function Batch([object[]]$Commands){
 if($Commands.Count -lt 1 -or $Commands.Count -gt 50){Fail 'BATCH_SIZE_INVALID'}
 $b=New-Object Text.StringBuilder;[void]$b.Append('{"halt":0,"cmd":{')
 for($i=0;$i -lt $Commands.Count;$i++){
  if($i -gt 0){[void]$b.Append(',')}
  [void]$b.Append((JsonQuote ('k'+$i)))
  [void]$b.Append(':')
  [void]$b.Append((JsonQuote ([string]$Commands[$i])))
 }
 [void]$b.Append('}}')
 return Http 'batch' $b.ToString()
}
function BResult([string]$Response,[int]$Idx,[string]$Expression){
 $k='k'+$Idx
 if($k -notmatch '^k[0-9]{1,2}$'){Fail 'BATCH_KEY_INVALID'}
 $path="'$.result.result."+ $k +"'"
 $errpath="'$.result.result_error."+ $k +"'"
 $sql="SELECT CASE WHEN json_valid(doc)<>1 THEN 'INVALID' WHEN json_type(doc,"+$errpath+") IS NOT NULL THEN 'ERROR' WHEN json_type(doc,"+$path+") IS NULL THEN 'MISSING' ELSE "+$Expression+" END FROM j;"
 return SqlJson $Response $sql
}
function VerifyBatchList([string]$Response,[int]$Idx,[string]$ItemPath){
 $p="'$.result.result.k"+$Idx+$ItemPath+"'"
 $expr="CASE WHEN json_type(doc,"+$p+")<>'array' THEN 'INVALID' WHEN json_array_length(doc,"+$p+")>1 THEN 'MULTIPLE' WHEN json_array_length(doc,"+$p+")=0 THEN 'NONE' WHEN coalesce(json_type(doc,'$.result.result_next.k"+$Idx+"'),'null')<>'null' THEN 'PAGING' ELSE CAST(json_extract(doc,"+$p+"||'[0].id') AS TEXT) END"
 return BResult $Response $Idx $expr
}
function SqlStatus([string]$Guid,[string]$State,[string]$CrmId,[string]$Kind){
 if($Guid -notmatch '^[0-9a-f-]{36}$'){Fail 'GUID_STATE_INVALID'}
 $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
 $sql="INSERT INTO msp_auto_ops(onec_guid,operation,crm_id,entity_kind,created_utc) VALUES ('"+$Guid+"','"+$State+"',"+$CrmId+",'"+$Kind+"','"+$stamp+"') ON CONFLICT(onec_guid) DO UPDATE SET operation=excluded.operation,crm_id=excluded.crm_id,entity_kind=excluded.entity_kind,created_utc=excluded.created_utc;"
 $null=Query $sql
}
function MarkDone([string]$Guid,[int]$CrmId,[int]$Kind){
 if($Guid -notmatch '^[0-9a-f-]{36}$' -or $CrmId -lt 1 -or @('3','4') -notcontains ([string]$Kind)){Fail 'MAP_INVALID'}
 $sql="BEGIN IMMEDIATE;INSERT INTO msp_auto_map(onec_guid,crm_id,entity_kind,mapped_utc) VALUES ('"+$Guid+"',"+$CrmId+","+$Kind+",datetime('now')) ON CONFLICT(onec_guid) DO UPDATE SET crm_id=excluded.crm_id,entity_kind=excluded.entity_kind,mapped_utc=excluded.mapped_utc;DELETE FROM msp_auto_outbox WHERE onec_guid='"+$Guid+"' AND change_kind='UPSERT';DELETE FROM msp_auto_ops WHERE onec_guid='"+$Guid+"';COMMIT;"
 $null=Query $sql
}
function Secret(){
 Add-Type -AssemblyName System.Security
 $file=Join-Path $script:root 'staging\bitrix-direct-private\bitrix-direct-webhook.dpapi'
 $buf=[IO.File]::ReadAllBytes($file);$clear=$null
 try{
  $clear=[Security.Cryptography.ProtectedData]::Unprotect($buf,[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-Bitrix24-Direct-Webhook-v1'),[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $url=[Text.Encoding]::UTF8.GetString($clear)
 }finally{
  [Array]::Clear($buf,0,$buf.Length)
  if($null -ne $clear){[Array]::Clear($clear,0,$clear.Length)}
 }
 if($url -notmatch '^https://b24-uwmjda\.bitrix24\.ru/rest/[1-9][0-9]{0,9}/[A-Za-z0-9_-]{8,128}/?$'){Fail 'BITRIX_WEBHOOK_INVALID'}
 $script:base=$url.TrimEnd('/')+'/'
}

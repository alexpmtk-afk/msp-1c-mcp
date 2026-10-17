#requires -version 2
# Fast, repeatable active-buyer count from TEST NewBase (daytime 1-minute monitor).
# Does not export customer records, identifiers, credentials or XML.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='IDENTITY'
$resp=$null
$state='C:\ProgramData\MspCustomerStore\state\msp-newbase-count-v2-status.txt'
$plain=$null
$encrypted=$null
$secure=$null
function Fail([string]$Reason){throw ('ONEC_'+$Reason)}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_REQUIRED'}
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'NOT_LOCAL_SERVICE'}
  $root='C:\ProgramData\MspCustomerStore'
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $config=Join-Path $root 'config\collector.ini'
  if(-not [IO.File]::Exists($secret) -or -not [IO.File]::Exists($config)){Fail 'MACHINE_SECRET_OR_CONFIG_MISSING'}
  $flags=[IO.File]::ReadAllText($config,[Text.Encoding]::ASCII)
  foreach($key in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($flags -notmatch ('(?m)^'+[regex]::Escape($key)+'\s*$')){Fail 'COLLECTOR_NOT_SAFE_IDLE'}
  }
  $phase='DECRYPT'
  Add-Type -AssemblyName System.Security
  $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
  $encrypted=[IO.File]::ReadAllBytes($secret)
  if($encrypted.Length -lt 32 -or $encrypted.Length -gt 8192){Fail 'CIPHERTEXT_SIZE_UNEXPECTED'}
  $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'DECRYPTED_LENGTH_INVALID'}
  $secure=New-Object Security.SecureString
  for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
  $secure.MakeReadOnly()
  [Array]::Clear($plain,0,$plain.Length)
  $plain=$null
  $credentials=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
  $table=[regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')
  $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
  $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
  $filter=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
  $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$table+'/$count?$filter='+[Uri]::EscapeDataString($filter)
  $phase='ODATA_GET_ONLY'
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET'
  $req.Proxy=$null
  $req.AllowAutoRedirect=$false
  $req.PreAuthenticate=$true
  $req.Credentials=$credentials.GetNetworkCredential()
  $req.Timeout=20000
  $req.ReadWriteTimeout=20000
  $resp=$req.GetResponse()
  if([int]$resp.StatusCode -ne 200){Fail 'HTTP_NOT_200'}
  $reader=New-Object IO.StreamReader -ArgumentList @($resp.GetResponseStream(),[Text.Encoding]::ASCII)
  try{
    $buf=New-Object char[] 64
    $n=$reader.Read($buf,0,$buf.Length)
    if($n -lt 1 -or $n -gt 20){Fail 'COUNT_LENGTH_UNEXPECTED'}
    $raw=(New-Object String -ArgumentList @($buf,0,$n)).Trim()
    if($raw -notmatch '^[0-9]{1,8}$'){Fail 'COUNT_NOT_INTEGER'}
    $count=[int]::Parse($raw)
    if($count -lt 1 -or $count -gt 1000000){Fail 'COUNT_OUT_OF_RANGE'}
  }finally{$reader.Close()}
  $stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  [IO.File]::WriteAllText($state,('UTC='+$stamp+';STATUS=PASS;IDENTITY=LOCAL_SERVICE;HTTP=200;BUYER_COUNT='+$count+';RECORDS_EXPORTED=0;ONEC_WRITES=0'),[Text.Encoding]::ASCII)
  'NEWBASE_COUNT_PROBE=PASS'
  'ONEC_HTTP=200'
  'ACTIVE_BUYER_COUNT='+$count
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=MSP_NEWBASE_COUNT_V2'
}catch [Net.WebException]{
  $gate='ODATA_TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  try{[IO.File]::WriteAllText($state,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate),[Text.Encoding]::ASCII)}catch{}
  'RESULT=FAIL;STAGE=MSP_NEWBASE_COUNT_V2;GATE='+$gate+';PHASE='+$phase
  exit 1
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^ONEC_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  try{[IO.File]::WriteAllText($state,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate),[Text.Encoding]::ASCII)}catch{}
  'RESULT=FAIL;STAGE=MSP_NEWBASE_COUNT_V2;GATE='+$gate+';PHASE='+$phase
  exit 1
}finally{
  if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
  if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
  if($null -ne $resp){$resp.Close()}
  if($null -ne $secure){$secure.Dispose()}
}

#requires -version 2
# S4 READ-ONLY capability survey: 1C TEST OData $metadata only.
# No SelectChanges, no POST, no writes to SQLite/1C/Bitrix.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='HOST'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\exchange-plan-metadata-s4.txt'
$encrypted=$null
$plain=$null
$secure=$null
$response=$null
function Fail([string]$Code){throw ('S4_'+$Code)}
function SafeName([string]$Value){
  if($Value.Length -gt 160){Fail 'PLAN_NAME_TOO_LONG'}
  $b=New-Object Text.StringBuilder
  foreach($ch in $Value.ToCharArray()){
    $num=[int]$ch
    if($num -ge 32 -and $num -le 126 -and $num -ne 92){
      [void]$b.Append($ch)
    }else{
      [void]$b.Append('\u'+$num.ToString('x4'))
    }
  }
  return $b.ToString()
}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS2_REQUIRED'}
  if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
  $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
  $cfg=Join-Path $root 'config\collector.ini'
  if(-not [IO.File]::Exists($secret) -or -not [IO.File]::Exists($cfg)){Fail 'MACHINE_CONFIG_MISSING'}
  if([IO.File]::Exists($status)){Fail 'SURVEY_ALREADY_EXISTS'}
  $settings=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
  foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
    if($settings -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'NOT_SAFE_IDLE'}
  }
  $phase='SERVICE_DPAPI'
  Add-Type -AssemblyName System.Security
  $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
  $encrypted=[IO.File]::ReadAllBytes($secret)
  if($encrypted.Length -lt 32 -or $encrypted.Length -gt 8192){Fail 'CIPHERTEXT_SIZE'}
  $plain=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  if($plain.Length -lt 2 -or $plain.Length -gt 1024 -or ($plain.Length % 2) -ne 0){Fail 'PASSWORD_SIZE'}
  $secure=New-Object Security.SecureString
  for($i=0;$i -lt $plain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($plain,$i))}
  $secure.MakeReadOnly()
  [Array]::Clear($plain,0,$plain.Length)
  $plain=$null
  $credentials=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
  $phase='ODATA_METADATA_GET'
  $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/$metadata'
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET'
  $req.Accept='application/xml'
  $req.Proxy=$null
  $req.AllowAutoRedirect=$false
  $req.PreAuthenticate=$true
  $req.Credentials=$credentials.GetNetworkCredential()
  $req.Timeout=30000
  $req.ReadWriteTimeout=30000
  $response=$req.GetResponse()
  if([int]$response.StatusCode -ne 200){Fail 'METADATA_HTTP_NOT_200'}
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
  try{
    $buf=New-Object char[] 8192
    $text=New-Object Text.StringBuilder
    $size=0
    do{
      $n=$reader.Read($buf,0,$buf.Length)
      $size+=$n
      if($size -gt 33554432){Fail 'METADATA_OVER_32M'}
      if($n -gt 0){[void]$text.Append($buf,0,$n)}
    }while($n -gt 0)
  }finally{$reader.Close()}
  $phase='PARSE_EXCHANGE_PLANS'
  $xml=New-Object Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.LoadXml($text.ToString())
  if($null -ne $xml.DocumentType){Fail 'DOCTYPE_NOT_ALLOWED'}
  $sets=@($xml.SelectNodes("//*[local-name()='EntitySet']"))
  if($sets.Count -lt 1 -or $sets.Count -gt 10000){Fail 'ENTITY_SET_COUNT_INVALID'}
  $plans=@()
  $names=@{}
  foreach($set in $sets){
    $a=$set.Attributes['Name']
    if($null -eq $a){continue}
    $name=$a.Value
    if($name -notlike 'ExchangePlan_*'){continue}
    if($names.ContainsKey($name)){Fail 'EXCHANGE_PLAN_DUPLICATE'}
    $names[$name]=$true
    $plans+=($name)
    if($plans.Count -gt 100){Fail 'EXCHANGE_PLAN_LIMIT'}
  }
  $selectChanges=$false
  $confirmChanges=$false
  foreach($func in @($xml.SelectNodes("//*[local-name()='FunctionImport']"))){
    $n=$func.Attributes['Name']
    if($null -eq $n){continue}
    if($n.Value -eq 'SelectChanges'){$selectChanges=$true}
    if($n.Value -eq 'ConfirmChanges'){$confirmChanges=$true}
  }
  $phase='WRITE_METADATA_SUMMARY'
  $receipt=New-Object Text.StringBuilder
  [void]$receipt.AppendLine('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+
    ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;HTTP=200;ENTITY_SETS='+$sets.Count+
    ';EXCHANGE_PLANS='+$plans.Count+';SELECTCHANGES_DECLARED='+$selectChanges+
    ';CONFIRMCHANGES_DECLARED='+$confirmChanges+
    ';ONEC_WRITES=0;BITRIX_CALLS=0')
  $ordered=@($plans | Sort-Object)
  for($i=0;$i -lt $ordered.Count;$i++){
    [void]$receipt.AppendLine(('PLAN_{0:D3}=' -f ($i+1))+(SafeName $ordered[$i]))
  }
  $fs=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
    $bytes=[Text.Encoding]::ASCII.GetBytes($receipt.ToString())
    $fs.Write($bytes,0,$bytes.Length)
    $fs.Flush()
  }finally{$fs.Close()}
  'S4_METADATA_HTTP=200'
  'S4_ENTITY_SETS='+$sets.Count
  'S4_EXCHANGE_PLAN_SETS='+$plans.Count
  'S4_SELECTCHANGES_DECLARED='+$selectChanges
  'S4_CONFIRMCHANGES_DECLARED='+$confirmChanges
  'S4_PLAN_NAMES_SAVED_LOCALLY=YES'
  'S4_CHANGE_REGISTRATION_READY=NOT_PROVEN'
  'ONEC_WRITES=NO'
  'BITRIX_CALLS=NO'
  'RESULT=PASS;STAGE=SRV_ONEC_EXCHANGE_METADATA_SURVEY'
}catch [Net.WebException]{
  $gate='ODATA_TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate),[Text.Encoding]::ASCII)}catch{}
  'RESULT=FAIL;STAGE=SRV_ONEC_EXCHANGE_METADATA_SURVEY;GATE='+$gate+';PHASE='+$phase
  exit 1
}catch{
  $gate='RUNTIME_ERROR'
  if($_.Exception.Message -match '^S4_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  try{[IO.File]::WriteAllText($status,('STATUS=FAIL;PHASE='+$phase+';GATE='+$gate),[Text.Encoding]::ASCII)}catch{}
  'RESULT=FAIL;STAGE=SRV_ONEC_EXCHANGE_METADATA_SURVEY;GATE='+$gate+';PHASE='+$phase
  exit 1
}finally{
  if($null -ne $response){$response.Close()}
  if($null -ne $plain){[Array]::Clear($plain,0,$plain.Length)}
  if($null -ne $encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}
  if($null -ne $secure){$secure.Dispose()}
}

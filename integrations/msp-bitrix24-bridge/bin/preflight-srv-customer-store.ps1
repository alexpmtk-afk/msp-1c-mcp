#requires -version 2
# Physical SRV read-only preflight for standalone 1C -> local index pipeline.
# No databases created. No filesystem mutations. Only OData TEST $metadata GET.
param([string]$ExpectedComputerName='SRV',[System.Management.Automation.PSCredential]$Credential)
$ErrorActionPreference='Stop'
$response=$null
$phase='PRECHECK'
function Fail([string]$Reason){throw ('PREFLIGHT_'+$Reason)}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'NOT_NATIVE_PS2'}
  $root='C:\ProgramData\MspBitrix24Bridge'
  $taskConfig=Join-Path $root 'config\bridge.ini'
  if(-not [IO.File]::Exists($taskConfig)){Fail 'BRIDGE_CONFIG_NOT_FOUND'}
  $contents=[IO.File]::ReadAllText($taskConfig)
  foreach($gate in @('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')){
    if(-not ($contents -match ('(?m)^'+[regex]::Escape($gate)+'\s*$'))){Fail 'BRIDGE_NOT_SAFE_IDLE'}
  }
  'HOST=SRV'
  'POWERSHELL_MAJOR=2'
  'CLR_VERSION='+[Environment]::Version.ToString()
  $drive=Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
  if($null -eq $drive){Fail 'DRIVE_READ_FAILED'}
  'C_FREE_GIB='+[Math]::Round(([double]$drive.FreeSpace/1073741824),2)
  $sqliteCli=Join-Path $root 'bin\sqlite3.exe'
  $sqliteProvider=Join-Path $root 'bin\System.Data.SQLite.dll'
  'SQLITE_CLI_PRESENT='+[IO.File]::Exists($sqliteCli)
  'SQLITE_PROVIDER_PRESENT='+[IO.File]::Exists($sqliteProvider)
  $v4='HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
  $hasV4=Test-Path $v4
  'NET4_FULL_REGKEY_PRESENT='+$hasV4
  'CUSTOMER_DB_EXISTS='+[IO.File]::Exists((Join-Path $root 'data\customers.db'))
  'SAFE_IDLE_VERIFIED=YES'
  if($null -eq $Credential){
    $secure=Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString
    if($null -eq $secure -or $secure.Length -eq 0){Fail 'PASSWORD_REQUIRED'}
    $Credential=New-Object System.Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
    $secure=$null
  }
  if($Credential.UserName -ne 'MCP_OData_ReadOnly'){Fail 'USERNAME_MISMATCH'}
  $phase='ODATA_METADATA'
  $url='http://127.0.0.1:8085/NewBase/odata/standard.odata/$metadata'
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET'
  $req.Proxy=$null
  $req.AllowAutoRedirect=$false
  $req.Credentials=$Credential.GetNetworkCredential()
  $req.PreAuthenticate=$true
  $req.Timeout=20000
  $req.ReadWriteTimeout=20000
  $response=$req.GetResponse()
  if([int]$response.StatusCode -ne 200){Fail 'ODATA_HTTP_NOT_200'}
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
  try {
    $buffer=New-Object char[] 8192
    $text=New-Object Text.StringBuilder
    $total=0
    do {
      $n=$reader.Read($buffer,0,$buffer.Length)
      $total+=$n
      if($total -gt 16777216){Fail 'METADATA_TOO_LARGE'}
      if($n -gt 0){[void]$text.Append($buffer,0,$n)}
    } while($n -gt 0)
  }finally{$reader.Close()}
  $phase='METADATA_PARSE'
  $xml=New-Object Xml.XmlDocument
  $xml.XmlResolver=$null
  $xml.LoadXml($text.ToString())
  $sets=@($xml.SelectNodes("//*[local-name()='EntitySet']"))
  $plans=@($sets | Where-Object {$_.GetAttribute('Name') -match '^ExchangePlan_'})
  'METADATA_ENTITY_SETS='+$sets.Count
  'EXCHANGE_PLAN_ENTITY_SETS='+$plans.Count
  foreach($x in @($plans | Select-Object -First 30)){
    'EXCHANGE_PLAN='+$x.GetAttribute('Name')
  }
  'EXCHANGE_PLAN_NAMES_TRUNCATED='+($plans.Count -gt 30)
  'PLAN_CHANGE_EVENTS_ACCESS=NOT_YET_VERIFIED'
  'CUSTOMER_RECORDS_EXPORTED=NO'
  'DATA_WRITES=NO'
  'FILES_CREATED=NO'
  'RESULT=PASS;STAGE=SRV_CUSTOMER_PIPELINE_PREFLIGHT'
}catch [Net.WebException]{
  $gate='ODATA_TRANSPORT_ERROR'
  if($null -ne $_.Exception.Response){$gate='HTTP_'+[int]$_.Exception.Response.StatusCode}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_PIPELINE_PREFLIGHT;GATE='+$gate
  'FAILURE_PHASE='+$phase
}catch{
  $msg=$_.Exception.Message
  $gate='RUNTIME_ERROR'
  if($msg -match '^PREFLIGHT_([A-Z0-9_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_CUSTOMER_PIPELINE_PREFLIGHT;GATE='+$gate
  'FAILURE_PHASE='+$phase
}finally{if($null -ne $response){$response.Close()}}

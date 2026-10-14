#requires -version 2
# One fixed GET to local SANDBOX NewBase OData; no caller-controlled URL or input.
# Outputs only a bounded numeric sample, never product or warehouse identifiers.
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$secret=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
[byte[]]$enc=$null
[byte[]]$plainBytes=$null
$response=$null
$stream=$null
$reader=$null
function Fail([string]$Code) { Write-Output $Code; exit 1 }
try {
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') { Fail 'ODATA_NOT_LOCAL_SERVICE' }
  if (-not (Test-Path -LiteralPath $secret -PathType Leaf)) { Fail 'ODATA_NOT_ENROLLED' }
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $enc=[IO.File]::ReadAllBytes($secret)
  $plainBytes=[Security.Cryptography.ProtectedData]::Unprotect($enc,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $password=[Text.Encoding]::UTF8.GetString($plainBytes)
  if (-not $password -or $password.Length -gt 256) { Fail 'ODATA_BAD_CREDENTIAL' }
  $url="http://127.0.0.1:8085/NewBase/odata/standard.odata/AccumulationRegister_ЗапасыНаСкладах/Balance(Dimensions='Номенклатура,СтруктурнаяЕдиница')?"+'$top=1&$format=json'
  $request=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $request.Method='GET'
  $request.Credentials=New-Object Net.NetworkCredential -ArgumentList @('MCP_OData_ReadOnly',$password)
  $request.PreAuthenticate=$true
  $request.Proxy=$null
  $request.AllowAutoRedirect=$false
  $request.Timeout=25000
  $request.ReadWriteTimeout=10000
  $request.Accept='application/json'
  $password=$null
  $response=$request.GetResponse()
  if ([int]$response.StatusCode -ne 200) { Fail 'ODATA_HTTP_ERROR' }
  $stream=$response.GetResponseStream()
  $reader=New-Object IO.StreamReader -ArgumentList @($stream,[Text.Encoding]::UTF8)
  $buffer=New-Object char[] 8192
  $count=0
  $body=New-Object Text.StringBuilder
  do {
    $got=$reader.Read($buffer,0,$buffer.Length)
    $count+=$got
    if ($count -gt 32768) { Fail 'ODATA_RESPONSE_TOO_LARGE' }
    if ($got -gt 0) { [void]$body.Append($buffer,0,$got) }
  } while ($got -gt 0)
  $json=$body.ToString()
  if ($json -notmatch '"value"\s*:\s*\[') { Fail 'ODATA_INVALID_RESPONSE' }
  # Fixed invariant field from the verified Balance response; no arbitrary query language.
  $match=[regex]::Match($json,'"КоличествоBalance"\s*:\s*(-?\d{1,9}(?:\.\d{1,3})?)')
  if (-not $match.Success) { Fail 'ODATA_NO_BALANCE_ROW' }
  Write-Output ('STOCK_Q_'+$match.Groups[1].Value)
  exit 0
} catch [Net.WebException] {
  if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) { Fail 'ODATA_AUTH_DENIED' }
  Fail 'ODATA_UNAVAILABLE'
} catch {
  Fail 'ODATA_READ_ERROR'
} finally {
  if ($null -ne $reader) { $reader.Close() }
  if ($null -ne $response) { $response.Close() }
  if ($null -ne $plainBytes) { [Array]::Clear($plainBytes,0,$plainBytes.Length) }
  if ($null -ne $enc) { [Array]::Clear($enc,0,$enc.Length) }
}

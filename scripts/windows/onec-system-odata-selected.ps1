#requires -version 2
# Sandbox NewBase only. Read-only OData GET with two strictly validated GUIDs.
# Only bounded quantity or allowlisted errors go to the VPS relay; no GUID echo.
param([Parameter(Mandatory=$true)][string]$ItemGuid,
      [Parameter(Mandatory=$true)][string]$WarehouseGuid)
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$secret=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
$clear=$null
$encrypted=$null
$response=$null
$reader=$null
function Fail([string]$code) { Write-Output $code; exit 1 }
function ValidateGuid([string]$value) {
  if ($value -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
      $value -eq '00000000-0000-0000-0000-000000000000') {
    Fail 'ODATA_SELECTED_INVALID_GUID'
  }
}
try {
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') {
    Fail 'ODATA_SELECTED_WRONG_IDENTITY'
  }
  ValidateGuid $ItemGuid
  ValidateGuid $WarehouseGuid
  if (-not (Test-Path -LiteralPath $secret -PathType Leaf)) { Fail 'ODATA_SELECTED_NO_CREDENTIAL' }
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  [byte[]]$encrypted=[IO.File]::ReadAllBytes($secret)
  [byte[]]$clear=[Security.Cryptography.ProtectedData]::Unprotect(
    $encrypted,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $password=[Text.Encoding]::UTF8.GetString($clear)
  if (-not $password -or $password.Length -gt 256) { Fail 'ODATA_SELECTED_BAD_CREDENTIAL' }
  $credentials=New-Object Net.NetworkCredential -ArgumentList @('MCP_OData_ReadOnly',$password)
  $password=$null
  $base="http://127.0.0.1:8085/NewBase/odata/standard.odata/AccumulationRegister_ЗапасыНаСкладах/Balance(Dimensions='Номенклатура,СтруктурнаяЕдиница')"
  $condition=("Номенклатура_Key eq guid'"+$ItemGuid+
    "' and СтруктурнаяЕдиница_Key eq guid'"+$WarehouseGuid+"'")
  $url=$base+'?$filter='+[Uri]::EscapeDataString($condition)+'&$top=2&$format=json'
  $request=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $request.Method='GET'
  $request.Credentials=$credentials
  $request.PreAuthenticate=$true
  $request.Proxy=$null
  $request.AllowAutoRedirect=$false
  $request.Timeout=25000
  $request.ReadWriteTimeout=10000
  $request.Accept='application/json'
  $response=$request.GetResponse()
  if ([int]$response.StatusCode -ne 200) { Fail 'ODATA_SELECTED_HTTP_ERROR' }
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
  $chunk=New-Object char[] 4096
  $builder=New-Object Text.StringBuilder
  $count=0
  do {
    $n=$reader.Read($chunk,0,$chunk.Length)
    $count+=$n
    if ($count -gt 32768) { Fail 'ODATA_SELECTED_RESPONSE_TOO_LARGE' }
    if ($n -gt 0) { [void]$builder.Append($chunk,0,$n) }
  } while($n -gt 0)
  $json=$builder.ToString()
  if ($json -match '"value"\s*:\s*\[\s*\]') { Fail 'ODATA_SELECTED_NO_ROW' }
  if ($json -notmatch '"value"\s*:\s*\[\s*\{') { Fail 'ODATA_SELECTED_INVALID_RESPONSE' }
  $mItem=[regex]::Matches($json,'"Номенклатура_Key"\s*:\s*"([0-9a-fA-F-]{36})"')
  $mWarehouse=[regex]::Matches($json,'"СтруктурнаяЕдиница_Key"\s*:\s*"([0-9a-fA-F-]{36})"')
  $mQuantity=[regex]::Matches($json,'"КоличествоBalance"\s*:\s*(-?\d{1,9}(?:\.\d{1,3})?)')
  if ($mItem.Count -ne 1 -or $mWarehouse.Count -ne 1 -or $mQuantity.Count -ne 1) {
    Fail 'ODATA_SELECTED_ROW_AMBIGUOUS'
  }
  if ($mItem[0].Groups[1].Value.ToLowerInvariant() -cne $ItemGuid -or
      $mWarehouse[0].Groups[1].Value.ToLowerInvariant() -cne $WarehouseGuid) {
    Fail 'ODATA_SELECTED_FILTER_MISMATCH'
  }
  $quantity=[decimal]::Parse($mQuantity[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
  $value=$quantity.ToString([Globalization.CultureInfo]::InvariantCulture)
  if ($value -notmatch '^-?[0-9]{1,9}(?:\.[0-9]{1,3})?$') {
    Fail 'ODATA_SELECTED_INVALID_QUANTITY'
  }
  Write-Output ('SELECTED_Q_'+$value)
  exit 0
} catch [Net.WebException] {
  if ($_.Exception.Response) {
    $http=[int]$_.Exception.Response.StatusCode
    if ($http -eq 401) { Fail 'ODATA_SELECTED_AUTH_DENIED' }
    if ($http -eq 404) { Fail 'ODATA_SELECTED_HTTP_NOT_FOUND' }
    Fail 'ODATA_SELECTED_HTTP_ERROR'
  }
  Fail 'ODATA_SELECTED_UNAVAILABLE'
} catch {
  Fail 'ODATA_SELECTED_READ_ERROR'
} finally {
  if ($null -ne $reader) { $reader.Close() }
  if ($null -ne $response) { $response.Close() }
  if ($null -ne $clear) { [Array]::Clear($clear,0,$clear.Length) }
  if ($null -ne $encrypted) { [Array]::Clear($encrypted,0,$encrypted.Length) }
}

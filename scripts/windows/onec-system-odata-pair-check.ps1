#requires -version 2
# LocalService fixed first-item-and-warehouse read-only filtered Balance sample.
# No parameters, arbitrary commands, writes, or raw identifiers exported.
# Both reference GUIDs stay local and are never printed or transmitted to GitHub.

$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$secret=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
[byte[]]$encrypted=$null
[byte[]]$clear=$null
$password=$null
$credentials=$null
$base="http://127.0.0.1:8085/NewBase/odata/standard.odata/AccumulationRegister_ЗапасыНаСкладах/Balance(Dimensions='Номенклатура,СтруктурнаяЕдиница')"
function ReadBounded([string]$url) {
  $response=$null
  $reader=$null
  try {
    $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
    $req.Method='GET'
    $req.Credentials=$credentials
    $req.PreAuthenticate=$true
    $req.Proxy=$null
    $req.AllowAutoRedirect=$false
    $req.Timeout=25000
    $req.ReadWriteTimeout=10000
    $req.Accept='application/json'
    $response=$req.GetResponse()
    if ([int]$response.StatusCode -ne 200) { throw 'NON_200' }
    $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
    $chars=New-Object char[] 4096
    $builder=New-Object Text.StringBuilder
    $size=0
    do {
      $n=$reader.Read($chars,0,$chars.Length)
      $size+=$n
      if ($size -gt 32768) { throw 'RESPONSE_TOO_LARGE' }
      if ($n -gt 0) { [void]$builder.Append($chars,0,$n) }
    } while ($n -gt 0)
    return $builder.ToString()
  } finally {
    if ($null -ne $reader) { $reader.Close() }
    if ($null -ne $response) { $response.Close() }
  }
}
function ReadRow([string]$json) {
  if ($json -notmatch '"value"\s*:\s*\[\s*\{') { throw 'NO_ROWS' }
  $pattern='(?i)"(Номенклатура_Key|СтруктурнаяЕдиница_Key)"\s*:\s*"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"'
  $matches=[regex]::Matches($json,$pattern)
  $values=@{}
  foreach($hit in $matches) {
    $key=$hit.Groups[1].Value
    if ($values.ContainsKey($key)) { throw 'MULTIPLE_DIMENSIONS' }
    $values[$key]=$hit.Groups[2].Value.ToLowerInvariant()
  }
  if (-not $values.ContainsKey('Номенклатура_Key') -or
      -not $values.ContainsKey('СтруктурнаяЕдиница_Key')) { throw 'DIMENSION_KEYS_MISSING' }
  $qtyMatches=[regex]::Matches($json,'"КоличествоBalance"\s*:\s*(-?\d{1,9}(?:\.\d{1,3})?)')
  if ($qtyMatches.Count -ne 1) { throw 'QUANTITY_NOT_UNIQUE' }
  $qty=[decimal]::Parse($qtyMatches[0].Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
  return @{ ItemGuid=$values['Номенклатура_Key']; WarehouseGuid=$values['СтруктурнаяЕдиница_Key']; Qty=$qty }
}
try {
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') {
    throw 'NOT_LOCAL_SERVICE'
  }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_POWERSHELL' }
  if (-not (Test-Path -LiteralPath $secret -PathType Leaf)) { throw 'CREDENTIAL_NOT_ENROLLED' }
  $phase='UNSEAL_READONLY_ACCOUNT'
  Add-Type -AssemblyName System.Security -ErrorAction Stop
  $encrypted=[IO.File]::ReadAllBytes($secret)
  $clear=[Security.Cryptography.ProtectedData]::Unprotect($encrypted,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $password=[Text.Encoding]::UTF8.GetString($clear)
  if (-not $password -or $password.Length -gt 256) { throw 'INVALID_CREDENTIAL' }
  $credentials=New-Object Net.NetworkCredential -ArgumentList @('MCP_OData_ReadOnly',$password)
  $password=$null
  $phase='GET_FIRST_BALANCE_ROW'
  $first=ReadRow (ReadBounded ($base+'?$top=1&$format=json'))
  $phase='GET_FILTERED_BALANCE'
  $condition=("Номенклатура_Key eq guid'"+$first['ItemGuid']+
      "' and СтруктурнаяЕдиница_Key eq guid'"+$first['WarehouseGuid']+"'")
  $filteredUrl=$base+'?$filter='+[Uri]::EscapeDataString($condition)+'&$top=2&$format=json'
  $second=ReadRow (ReadBounded $filteredUrl)
  $phase='VERIFY_FILTERED_MATCH'
  if ($second['ItemGuid'] -ne $first['ItemGuid'] -or $second['WarehouseGuid'] -ne $first['WarehouseGuid']) {
    throw 'FILTER_RETURNED_WRONG_PAIR'
  }
  if ($second.Qty -ne $first.Qty) { throw 'QUANTITY_MISMATCH' }
  $quantity=$first.Qty.ToString([Globalization.CultureInfo]::InvariantCulture)
  if ($quantity -notmatch '^-?[0-9]{1,9}(?:\.[0-9]{1,3})?
} catch {
  $known=@('WRONG_MACHINE','WRONG_POWERSHELL','WRONG_OS','ADMIN_REQUIRED',
    'CREDENTIAL_NOT_ENROLLED','INVALID_CREDENTIAL','NON_200',
    'RESPONSE_TOO_LARGE','NO_ROWS','MULTIPLE_DIMENSIONS',
    'DIMENSION_KEYS_MISSING','QUANTITY_NOT_UNIQUE',
    'FILTER_RETURNED_WRONG_PAIR','QUANTITY_MISMATCH')
  $reason=$_.Exception.Message
  if ($known -notcontains $reason) { $reason='READ_ERROR' }
  # Only fixed error marker may reach the queue. No HTTP bodies, GUIDs or secrets.
  Write-Output 'ODATA_PAIR_READ_FAILED'
  exit 1
} finally {
  $password=$null
  $credentials=$null
  if ($null -ne $clear) { [Array]::Clear($clear,0,$clear.Length) }
  if ($null -ne $encrypted) { [Array]::Clear($encrypted,0,$encrypted.Length) }
}
) { throw 'INVALID_QUANTITY' }
  Write-Output ('PAIR_Q_'+$quantity)
  exit 0
} catch {
  $known=@('WRONG_MACHINE','WRONG_POWERSHELL','WRONG_OS','ADMIN_REQUIRED',
    'CREDENTIAL_NOT_ENROLLED','INVALID_CREDENTIAL','NON_200',
    'RESPONSE_TOO_LARGE','NO_ROWS','MULTIPLE_DIMENSIONS',
    'DIMENSION_KEYS_MISSING','QUANTITY_NOT_UNIQUE',
    'FILTER_RETURNED_WRONG_PAIR','QUANTITY_MISMATCH')
  $reason=$_.Exception.Message
  if ($known -notcontains $reason) { $reason='READ_ERROR' }
  Write-Output ('RESULT=FAIL;STAGE='+$phase+';GATE='+$reason)
  exit 1
} finally {
  $password=$null
  $credentials=$null
  if ($null -ne $clear) { [Array]::Clear($clear,0,$clear.Length) }
  if ($null -ne $encrypted) { [Array]::Clear($encrypted,0,$encrypted.Length) }
}

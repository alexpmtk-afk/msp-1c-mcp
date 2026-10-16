#requires -version 2
# Fixed read-only LocalService NewBase OData V4 exact two-card stock acceptance (read-only).
# This helper NEVER receives a URL/command/GUID from any end-user.
# Accepted user keys: only product Description or published Артикул.
# 1C Code is an output-only identifier for disambiguating duplicate cards.
param(
  [Parameter(Mandatory=$true)][string]$Kind,
  [Parameter(Mandatory=$true)][string]$ItemB64,
  [Parameter(Mandatory=$true)][string]$WarehouseB64
)
$ErrorActionPreference='Stop'
$root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspOnecAgent'
$secret=Join-Path (Join-Path $root 'secrets') 'odata-readonly.machine.dpapi'
$base='http://127.0.0.1:8085/NewBase/odata/standard.odata/'
$credential=$null
[byte[]]$encrypted=$null
[byte[]]$clear=$null
$serializer=$null
$warehouseCache=@{}
$diagStage='START'
$diagFile=Join-Path (Join-Path $root 'state') 'natural-stock-v4-card-smoke-result.txt'
$MAX_ITEMS=50
$MAX_WAREHOUSES=50
$MAX_RESPONSE=262144

function Term([string]$value,[int]$limit) {
  if ($null -eq $value -or $value.Length -lt 1 -or $value.Length -gt $limit -or
      $value -cne $value.Trim()) { throw 'INVALID_TERM' }
  if ($value.Normalize([Text.NormalizationForm]::FormC) -cne $value -or
      $value -match '[\p{Cc}\p{Cf}\p{Cs}\p{Co}\p{Cn}\p{Zl}\p{Zp}]') {
    throw 'INVALID_TERM'
  }
  return $value
}
function Decode([string]$token,[int]$max) {
  if ($token -notmatch '^[A-Za-z0-9_-]+$') { throw 'INVALID_BASE64URL' }
  $padded=$token.Replace('-','+').Replace('_','/')
  $padded=$padded+('=' * ((4-$padded.Length%4)%4))
  $bytes=[Convert]::FromBase64String($padded)
  $text=(New-Object Text.UTF8Encoding -ArgumentList @($false,$true)).GetString($bytes)
  $check=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text)).TrimEnd('=').Replace('+','-').Replace('/','_')
  if ($check -cne $token) { throw 'NONCANONICAL_BASE64URL' }
  return (Term $text $max)
}
function GuidCheck([string]$guid) {
  if ($guid -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' -or
      $guid -eq '00000000-0000-0000-0000-000000000000') { throw 'INVALID_1C_GUID' }
  return $guid.ToLowerInvariant()
}
function FixedGet([string]$path,[int]$limit) {
  if ($path.Length -gt 512 -or $path -match '^(?i)https?:|[\r\n#]') {
    throw 'INVALID_FIXED_QUERY'
  }
  $request=$null;$response=$null;$reader=$null
  try {
    $request=[Net.HttpWebRequest][Net.WebRequest]::Create($base+$path)
    $request.Method='GET'
    $request.Credentials=$credential
    $request.PreAuthenticate=$true
    $request.Proxy=$null
    $request.AllowAutoRedirect=$false
    $request.Timeout=30000
    $request.ReadWriteTimeout=15000
    $request.Accept='application/json'
    $response=$request.GetResponse()
    if ([int]$response.StatusCode -ne 200) { throw 'ODATA_NON_200' }
    $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::UTF8)
    $buffer=New-Object char[] 4096
    $out=New-Object Text.StringBuilder
    $count=0
    do {
      $n=$reader.Read($buffer,0,$buffer.Length)
      $count+=$n
      if ($count -gt $limit) { throw 'ODATA_TOO_LARGE' }
      if ($n -gt 0) { [void]$out.Append($buffer,0,$n) }
    } while ($n -gt 0)
    return $out.ToString()
  } finally {
    if ($null -ne $reader) { $reader.Close() }
    if ($null -ne $response) { $response.Close() }
  }
}
function Rows([string]$path,[int]$cap) {
  $raw=FixedGet $path 131072
  $data=$serializer.DeserializeObject($raw)
  if ($null -eq $data -or -not $data.ContainsKey('value')) {
    throw 'INVALID_ODATA_PAYLOAD'
  }
  foreach($next in @('odata.nextLink','@odata.nextLink','__next','nextLink')) {
    if ($data.ContainsKey($next) -and $data[$next]) { throw 'PAGED_ODATA_RESULT' }
  }
  $records=@($data['value'])
  if ($records.Count -gt $cap) { throw 'ODATA_RESULT_TOO_LARGE' }
  foreach($record in $records) {
    if ($null -eq $record -or -not ($record -is [Collections.IDictionary])) {
      throw 'INVALID_ODATA_ROW'
    }
  }
  return ,$records
}
function ExactFilter([string]$field,[string]$text) {
  if (-not (@('Description','Артикул','Ref_Key') -ccontains $field)) {
    throw 'FIELD_NOT_ALLOWED'
  }
  $escaped=$text.Replace("'","''")
  $predicate=($field+" eq '"+$escaped+"'")
  if ($field -eq 'Ref_Key') {
    $predicate=("Ref_Key eq guid'"+(GuidCheck $text)+"'")
  }
  return [Uri]::EscapeDataString($predicate)
}
function UnitName([string]$guid) {
  $id=GuidCheck $guid
  if ($warehouseCache.ContainsKey($id)) { return $warehouseCache[$id] }
  $filter=ExactFilter 'Ref_Key' $id
  $rows=Rows ('Catalog_СтруктурныеЕдиницы?$select=Ref_Key,Description&$filter='+$filter+'&$top=2&$format=json') 2
  if ($rows.Count -ne 1) { throw 'UNIT_REF_NOT_UNIQUE' }
  if ((GuidCheck $rows[0]['Ref_Key']) -ne $id) { throw 'UNIT_REF_MISMATCH' }
  $label=[string]$rows[0]['Description']
  # Real 1C catalog names may contain leading whitespace; preserve it
  # exactly while excluding unsafe controls and unreasonably long fields.
  if (-not $label.Trim() -or $label.Length -gt 100 -or
      $label -match '[\p{Cc}\p{Cf}\p{Cs}\p{Co}\p{Cn}\p{Zl}\p{Zp}]') {
    throw 'INVALID_1C_UNIT_NAME'
  }
  $warehouseCache[$id]=$label
  return $label
}
function Quantity($raw) {
  if ($null -eq $raw -or $raw -is [bool]) { throw 'INVALID_QUANTITY' }
  $value=[Convert]::ToString($raw,[Globalization.CultureInfo]::InvariantCulture)
  if ($value -notmatch '^-?[0-9]{1,9}(\.[0-9]{1,3})?$') { throw 'INVALID_QUANTITY' }
  return $value
}
function StatusResult([string]$status) {
  if ($status -notmatch '^(ITEM_NOT_FOUND|ITEM_RESULT_INCOMPLETE|WAREHOUSE_NOT_FOUND|WAREHOUSE_AMBIGUOUS|WAREHOUSE_RESULT_INCOMPLETE|BALANCE_RESULT_INCOMPLETE|UNAVAILABLE)$') {
    $status='UNAVAILABLE'
  }
  return @{status=$status}
}
function PrintResult($output) {
  if ($output['status'] -ne 'PASS' -and -not (Test-Path -LiteralPath $diagFile)) {
    $safeStatus=$output['status']
    if ($safeStatus -notmatch '^[A-Z_]{1,60}$') { $safeStatus='UNKNOWN_STATUS' }
    $report=('STAGE='+$diagStage+[Environment]::NewLine+'REASON='+$safeStatus+
      [Environment]::NewLine+'ERROR_TYPE=STATUS'+[Environment]::NewLine+'RESULT=FAIL')
    [IO.File]::WriteAllText($diagFile,$report,[Text.Encoding]::ASCII)
  }
  $json=ConvertTo-NaturalStockJson $output
  [byte[]]$bytes=[Text.Encoding]::UTF8.GetBytes($json)
  if ($bytes.Length -gt $MAX_RESPONSE) { throw 'RESULT_TOO_LARGE' }
  $encoded=[Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
  Write-Output ('NAT_'+$encoded)
}

try {
  $diagStage='IDENTITY'
  if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19') {
    throw 'WRONG_IDENTITY'
  }
  if ($PSVersionTable.PSVersion.Major -ne 2) { throw 'WRONG_POWERSHELL' }
  if (-not (@('name','article') -ccontains $Kind)) { throw 'INVALID_LOOKUP_MODE' }
  $diagStage='DECODE_INPUT'
  $item=Decode $ItemB64 $(if($Kind -eq 'name'){160}else{96})
  $warehouse=$null
  if ($WarehouseB64 -ne '-') { $warehouse=Decode $WarehouseB64 100 }
  $diagStage='READ_CREDENTIAL_FILE'
  if (-not (Test-Path -LiteralPath $secret -PathType Leaf)) { throw 'ODATA_CREDENTIAL_NOT_ENROLLED' }
  $diagStage='LOAD_SECURITY_ASSEMBLY'
  Add-Type -AssemblyName System.Security
  $diagStage='LOAD_CLR2_JSON_LIBRARY'
  $jsonLibrary=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'onec-legacy-json.ps1'
  if (-not (Test-Path -LiteralPath $jsonLibrary -PathType Leaf)) { throw 'JSON_LIB_NOT_INSTALLED' }
  . $jsonLibrary
  $diagStage='LOAD_FIXED_JSON_WRITER'
  $writerLibrary=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'onec-natural-stock-json-writer.ps1'
  if (-not (Test-Path -LiteralPath $writerLibrary -PathType Leaf)) { throw 'JSON_WRITER_NOT_INSTALLED' }
  . $writerLibrary
  $diagStage='CREATE_JSON_SERIALIZER'
  $serializer=New-Object MspLegacyJson
  $serializer.MaxJsonLength=262144
  $diagStage='DECRYPT_CREDENTIAL'
  $encrypted=[IO.File]::ReadAllBytes($secret)
  $clear=[Security.Cryptography.ProtectedData]::Unprotect(
      $encrypted,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  $password=[Text.Encoding]::UTF8.GetString($clear)
  if (-not $password -or $password.Length -gt 256) { throw 'INVALID_CREDENTIAL' }
  $diagStage='CREATE_1C_CREDENTIAL'
  $credential=New-Object Net.NetworkCredential -ArgumentList @('MCP_OData_ReadOnly',$password)
  $password=$null

  $field=$(if($Kind -eq 'name'){'Description'}else{'Артикул'})
  $filter=ExactFilter $field $item
  $itemPath='Catalog_Номенклатура?$select=Ref_Key,Description,Code,Артикул&$filter='+$filter+'&$top=51&$format=json'
  $diagStage='READ_CATALOG_ITEMS'
  $matched=Rows $itemPath 51
  if ($matched.Count -gt $MAX_ITEMS) { PrintResult (StatusResult 'ITEM_RESULT_INCOMPLETE'); exit 0 }
  if ($matched.Count -eq 0) { PrintResult (StatusResult 'ITEM_NOT_FOUND'); exit 0 }

  $chosenWarehouse=$null
  if ($null -ne $warehouse) {
    $wf=ExactFilter 'Description' $warehouse
    $diagStage='READ_STRUCTURAL_UNIT'
    $units=Rows ('Catalog_СтруктурныеЕдиницы?$select=Ref_Key,Description&$filter='+$wf+'&$top=2&$format=json') 2
    if ($units.Count -eq 0) { PrintResult (StatusResult 'WAREHOUSE_NOT_FOUND'); exit 0 }
    if ($units.Count -gt 1) { PrintResult (StatusResult 'WAREHOUSE_AMBIGUOUS'); exit 0 }
    $chosenWarehouse=GuidCheck $units[0]['Ref_Key']
  }
  $items=@()
  $uniqueItems=@{}
  foreach($record in $matched) {
    $diagStage='VALIDATE_CATALOG_RECORD'
    $guid=GuidCheck $record['Ref_Key']
    if ($uniqueItems.ContainsKey($guid)) { throw 'DUPLICATE_ITEM' }
    $uniqueItems[$guid]=$true
    $name=[string]$record['Description']
    $art=$record['Артикул']
    $code=$record['Code']
    if (-not $name -or $name.Length -gt 160) { throw 'INVALID_ITEM_NAME' }
    if ($art -eq '') { $art=$null }
    if ($code -eq '') { $code=$null }
    if ($art -ne $null -and ([string]$art).Length -gt 96) { throw 'INVALID_ARTICLE' }
    if ($code -ne $null -and ([string]$code).Length -gt 96) { throw 'INVALID_CODE' }
    if ($field -eq 'Description' -and $name -cne $item) { throw 'WRONG_ITEM_MATCH' }
    if ($field -eq 'Артикул' -and $art -cne $item) { throw 'WRONG_ARTICLE_MATCH' }
    $predicate=("Номенклатура_Key eq guid'"+$guid+"'")
    if ($null -ne $chosenWarehouse) {
      $predicate+=(" and СтруктурнаяЕдиница_Key eq guid'"+$chosenWarehouse+"'")
    }
    $query=[Uri]::EscapeDataString($predicate)
    $balanceUrl="AccumulationRegister_ЗапасыНаСкладах/Balance(Dimensions='Номенклатура,СтруктурнаяЕдиница')?"+'$filter='+$query+'&$top=51&$format=json'
    $diagStage='READ_STOCK_REGISTER'
    $balances=Rows $balanceUrl 51
    if ($balances.Count -gt $MAX_WAREHOUSES) {
      PrintResult (StatusResult 'BALANCE_RESULT_INCOMPLETE'); exit 0
    }
    $amount=[decimal]0
    $found=@()
    $seen=@{}
    foreach($line in $balances) {
      $diagStage='VALIDATE_BALANCE_ROW'
      if ((GuidCheck $line['Номенклатура_Key']) -ne $guid) { throw 'WRONG_BALANCE_ITEM' }
      $unit=GuidCheck $line['СтруктурнаяЕдиница_Key']
      if ($null -ne $chosenWarehouse -and $unit -ne $chosenWarehouse) {
        throw 'WRONG_BALANCE_WAREHOUSE'
      }
      if ($seen.ContainsKey($unit)) { throw 'DUPLICATE_ITEM_WAREHOUSE' }
      $seen[$unit]=$true
      $quantity=Quantity $line['КоличествоBalance']
      $amount += [decimal]::Parse($quantity,[Globalization.CultureInfo]::InvariantCulture)
      $diagStage='READ_UNIT_FOR_BALANCE'
      $label=UnitName $unit
      $found+=@(@{name=$label;quantity=$quantity;balance_state='ROW_PRESENT'})
    }
    $balanceState=$(if($found.Count -gt 0){'HAS_BALANCE_ROWS'}else{'NO_BALANCE_ROW'})
    if ($null -ne $warehouse -and $found.Count -eq 0) {
      $found+=@(@{name=$warehouse;quantity='0';balance_state='NO_BALANCE_ROW'})
    }
    $diagStage='ASSEMBLE_ITEM_RESULT'
    $items+=@(@{
      name=$name;article=$art;code=$code;
      total_quantity=$amount.ToString([Globalization.CultureInfo]::InvariantCulture);
      balance_state=$balanceState;
      warehouses=@($found)
    })
  }
  $output=@{
    status='PASS';search_kind=$Kind;search_term=$item;
    requested_warehouse=$warehouse;match_count=[int]$items.Count;items=@($items);
    source='1C NewBase Balance';mode='read-only'
  }
  $diagStage='ASSERT_TWO_REAL_CARDS'
  if ($Kind -cne 'name' -or $item -cne 'Слэмбол 6 кг' -or
      $warehouse -cne 'Основной склад' -or $items.Count -ne 2) {
    throw 'CARD_COUNT_OR_QUERY_CHANGED'
  }
  $seenA=$false;$seenB=$false
  foreach($card in $items) {
    if ($card['name'] -cne $item -or
        ($null -ne $card['article'] -and [string]$card['article'] -cne '')) {
      throw 'CARD_NAME_OR_ARTICLE_CHANGED'
    }
    $units=@($card['warehouses'])
    if ($units.Count -ne 1 -or $units[0]['name'] -cne $warehouse) {
      throw 'CARD_WAREHOUSE_CHANGED'
    }
    if ($card['code'] -ceq 'НФ-00001359') {
      if ($seenA -or $card['total_quantity'] -cne '6' -or
          $card['balance_state'] -cne 'HAS_BALANCE_ROWS' -or
          $units[0]['quantity'] -cne '6' -or
          $units[0]['balance_state'] -cne 'ROW_PRESENT') {
        throw 'CARD_FIRST_BALANCE_CHANGED'
      }
      $seenA=$true
    } elseif ($card['code'] -ceq 'НФ-00000879') {
      if ($seenB -or $card['total_quantity'] -cne '0' -or
          $card['balance_state'] -cne 'NO_BALANCE_ROW' -or
          $units[0]['quantity'] -cne '0' -or
          $units[0]['balance_state'] -cne 'NO_BALANCE_ROW') {
        throw 'CARD_SECOND_BALANCE_CHANGED'
      }
      $seenB=$true
    } else { throw 'UNEXPECTED_CARD' }
  }
  if (-not $seenA -or -not $seenB) { throw 'EXPECTED_CARD_MISSING' }
  $diagStage='SERIALIZE_COMPLETE_RESULT'
  PrintResult $output
  [IO.File]::WriteAllText($diagFile,('STAGE=COMPLETED'+[Environment]::NewLine+
    'REASON=NONE'+[Environment]::NewLine+'ERROR_TYPE=NONE'+[Environment]::NewLine+
    'RESULT=PASS'),[Text.Encoding]::ASCII)
  exit 0
} catch {
  # Only allowlisted machine-readable identifiers. Never write exception text,
  # OData response, credentials, item/warehouse GUIDs or HTTP URLs.
  $reason='UNCLASSIFIED'
  $allow=@('WRONG_IDENTITY','WRONG_POWERSHELL','INVALID_LOOKUP_MODE',
    'INVALID_BASE64URL','INVALID_TERM','NONCANONICAL_BASE64URL',
    'ODATA_CREDENTIAL_NOT_ENROLLED','INVALID_CREDENTIAL','JSON_LIB_NOT_INSTALLED',
    'INVALID_ODATA_PAYLOAD','PAGED_ODATA_RESULT','ODATA_RESULT_TOO_LARGE',
    'INVALID_ODATA_ROW','INVALID_1C_GUID','WRONG_ITEM_MATCH',
    'WRONG_ARTICLE_MATCH','INVALID_ITEM_NAME','INVALID_ARTICLE','INVALID_CODE',
    'INVALID_QUANTITY','DUPLICATE_ITEM','DUPLICATE_ITEM_WAREHOUSE',
    'WRONG_BALANCE_ITEM','WRONG_BALANCE_WAREHOUSE','UNIT_REF_NOT_UNIQUE',
    'UNIT_REF_MISMATCH','INVALID_1C_UNIT_NAME','ODATA_NON_200','ODATA_TOO_LARGE',
    'INVALID_FIXED_QUERY','RESULT_TOO_LARGE','FIELD_NOT_ALLOWED',
    'JSON_WRITER_NOT_INSTALLED','JSON_TOTAL_MISMATCH','JSON_INVALID_CARD',
    'CARD_COUNT_OR_QUERY_CHANGED','CARD_NAME_OR_ARTICLE_CHANGED',
    'CARD_WAREHOUSE_CHANGED','CARD_FIRST_BALANCE_CHANGED',
    'CARD_SECOND_BALANCE_CHANGED','UNEXPECTED_CARD','EXPECTED_CARD_MISSING')
  if ($allow -contains $_.Exception.Message) { $reason=$_.Exception.Message }
  if ($_.Exception -is [Net.WebException]) {
    $reason='WEB_EXCEPTION'
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $http=[int]$_.Exception.Response.StatusCode
      if ($http -eq 400) { $reason='HTTP_400' }
      if ($http -eq 401) { $reason='HTTP_401' }
      if ($http -eq 403) { $reason='HTTP_403' }
      if ($http -eq 404) { $reason='HTTP_404' }
      if ($http -ge 500) { $reason='HTTP_5XX' }
    }
  }
  $type=$_.Exception.GetType().Name
  if ($type -notmatch '^[A-Za-z]{1,45}$') { $type='OTHER' }
  try {
    $report=('STAGE='+$diagStage+[Environment]::NewLine+'REASON='+$reason+
      [Environment]::NewLine+'ERROR_TYPE='+$type+[Environment]::NewLine+
      'RESULT=FAIL')
    [IO.File]::WriteAllText($diagFile,$report,[Text.Encoding]::ASCII)
  } catch {}
  # Never expose an exception/URL/credential/raw item record.
  try {
    if ($null -eq $serializer) {
      $jsonLibrary=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'onec-legacy-json.ps1'
      if (Test-Path -LiteralPath $jsonLibrary -PathType Leaf) { . $jsonLibrary }
      $writerLibrary=Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'onec-natural-stock-json-writer.ps1'
      if (Test-Path -LiteralPath $writerLibrary -PathType Leaf) { . $writerLibrary }
      $serializer=New-Object MspLegacyJson
    }
    PrintResult (StatusResult 'UNAVAILABLE')
  } catch {
    Write-Output 'ODATA_NATURAL_UNAVAILABLE'
  }
  exit 1
} finally {
  $credential=$null
  if ($null -ne $clear) { [Array]::Clear($clear,0,$clear.Length) }
  if ($null -ne $encrypted) { [Array]::Clear($encrypted,0,$encrypted.Length) }
}

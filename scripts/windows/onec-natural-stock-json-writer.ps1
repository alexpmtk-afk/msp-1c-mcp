#requires -version 2
# Strict PowerShell 2 stock JSON writer. No generic Hashtable/PSObject serializer.
# Only fixed, human-readable fields may leave physical SRV.
function StockJsonString($value) {
  if ($null -eq $value) { return 'null' }
  if (-not ($value -is [string])) { throw 'JSON_TEXT_TYPE' }
  if ($value.Length -gt 160) { throw 'JSON_TEXT_LENGTH' }
  if ($value -match '(?i)[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}') {
    throw 'INTERNAL_GUID_NOT_ALLOWED'
  }
  $out=New-Object Text.StringBuilder
  [void]$out.Append('"')
  foreach($ch in $value.ToCharArray()) {
    $n=[int][char]$ch
    if($n -eq 34) { [void]$out.Append('\"') }
    elseif($n -eq 92) { [void]$out.Append('\\') }
    elseif($n -eq 8) { [void]$out.Append('\b') }
    elseif($n -eq 9) { [void]$out.Append('\t') }
    elseif($n -eq 10) { [void]$out.Append('\n') }
    elseif($n -eq 12) { [void]$out.Append('\f') }
    elseif($n -eq 13) { [void]$out.Append('\r') }
    elseif($n -lt 32 -or ($n -ge 55296 -and $n -le 57343)) {
      [void]$out.Append('\u')
      [void]$out.Append($n.ToString('x4',[Globalization.CultureInfo]::InvariantCulture))
    } else { [void]$out.Append($ch) }
  }
  [void]$out.Append('"')
  return $out.ToString()
}
function StockJsonQuantity($value) {
  if (-not ($value -is [string]) -or
      $value -notmatch '^-?[0-9]{1,9}(\.[0-9]{1,3})?$') {
    throw 'JSON_INVALID_QUANTITY'
  }
  return $value
}
function ConvertTo-NaturalStockJson($result) {
  if (-not ($result -is [Collections.IDictionary])) { throw 'JSON_INVALID_RESULT' }
  $status=[string]$result['status']
  if ($status -ne 'PASS') {
    if ($status -notmatch '^(ITEM_NOT_FOUND|ITEM_RESULT_INCOMPLETE|WAREHOUSE_NOT_FOUND|WAREHOUSE_AMBIGUOUS|WAREHOUSE_RESULT_INCOMPLETE|BALANCE_RESULT_INCOMPLETE|UNAVAILABLE)$') {
      throw 'JSON_INVALID_STATUS'
    }
    return ('{"status":'+(StockJsonString $status)+'}')
  }
  if (@('name','article') -cnotcontains [string]$result['search_kind']) { throw 'JSON_BAD_SELECTOR' }
  if ([string]$result['source'] -cne '1C NewBase Balance' -or
      [string]$result['mode'] -cne 'read-only') { throw 'JSON_BAD_SOURCE' }
  $cards=@($result['items'])
  $count=$cards.Count
  if ($count -lt 1 -or $count -gt 50 -or [int]$result['match_count'] -ne $count) {
    throw 'JSON_INVALID_ITEM_COUNT'
  }
  $encodedCards=New-Object 'System.Collections.Generic.List[string]'
  foreach($card in $cards) {
    if (-not ($card -is [Collections.IDictionary])) { throw 'JSON_INVALID_CARD' }
    $rows=@($card['warehouses'])
    if ($rows.Count -gt 50) { throw 'JSON_TOO_MANY_UNITS' }
    $encodedRows=New-Object 'System.Collections.Generic.List[string]'
    [decimal]$total=0
    [bool]$hasPhysicalRow=$false
    foreach($row in $rows) {
      if (-not ($row -is [Collections.IDictionary])) { throw 'JSON_INVALID_UNIT' }
      $quantity=StockJsonQuantity ([string]$row['quantity'])
      $state=[string]$row['balance_state']
      if (@('ROW_PRESENT','NO_BALANCE_ROW') -cnotcontains $state) { throw 'JSON_INVALID_ROW_STATE' }
      if ($state -eq 'NO_BALANCE_ROW' -and $quantity -ne '0') { throw 'JSON_MISSING_NOT_ZERO' }
      if ($state -eq 'ROW_PRESENT') { $hasPhysicalRow=$true }
      $total += [decimal]::Parse($quantity,[Globalization.CultureInfo]::InvariantCulture)
      $encodedRows.Add(('{"name":'+(StockJsonString ([string]$row['name']))+
        ',"quantity":'+(StockJsonString $quantity)+
        ',"balance_state":'+(StockJsonString $state)+'}'))
    }
    $overall=[string]$card['balance_state']
    if (@('HAS_BALANCE_ROWS','NO_BALANCE_ROW') -cnotcontains $overall) { throw 'JSON_INVALID_BALANCE_STATE' }
    if (($overall -eq 'HAS_BALANCE_ROWS') -ne $hasPhysicalRow) { throw 'JSON_BALANCE_STATE_MISMATCH' }
    $qty=StockJsonQuantity ([string]$card['total_quantity'])
    if ([decimal]::Parse($qty,[Globalization.CultureInfo]::InvariantCulture) -ne $total) {
      throw 'JSON_TOTAL_MISMATCH'
    }
    $encodedCards.Add(('{"name":'+(StockJsonString ([string]$card['name']))+
      ',"article":'+(StockJsonString $card['article'])+
      ',"code":'+(StockJsonString $card['code'])+
      ',"total_quantity":'+(StockJsonString $qty)+
      ',"balance_state":'+(StockJsonString $overall)+
      ',"warehouses":['+([string]::Join(',',$encodedRows.ToArray()))+']}'))
  }
  $json=('{"status":"PASS","search_kind":'+(StockJsonString ([string]$result['search_kind']))+
    ',"search_term":'+(StockJsonString ([string]$result['search_term']))+
    ',"requested_warehouse":'+(StockJsonString $result['requested_warehouse'])+
    ',"match_count":'+$count.ToString([Globalization.CultureInfo]::InvariantCulture)+
    ',"items":['+([string]::Join(',',$encodedCards.ToArray()))+']'+
    ',"source":"1C NewBase Balance","mode":"read-only"}')
  if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 262144) { throw 'JSON_OVERSIZE' }
  return $json
}

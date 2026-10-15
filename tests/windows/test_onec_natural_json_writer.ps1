#requires -version 2
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..')).Path
. (Join-Path $root 'scripts\windows\onec-natural-stock-json-writer.ps1')
. (Join-Path $root 'scripts\windows\onec-legacy-json.ps1')
$ser=New-Object MspLegacyJson
function Assert([bool]$p,[string]$label) { if(-not $p){throw ('ASSERT_'+$label)} }
function Row([string]$code,[string]$qty,[string]$state,[string]$rowState) {
  return @{
    name='Слэмбол 6 кг';article=$null;code=$code;total_quantity=$qty;
    balance_state=$state;
    warehouses=@(@{name='Основной склад';quantity=$qty;balance_state=$rowState})
  }
}
$two=@{
  status='PASS';search_kind='name';search_term='Слэмбол 6 кг';
  requested_warehouse='Основной склад';match_count=2;
  source='1C NewBase Balance';mode='read-only';
  items=@((Row 'НФ-00001359' '6' 'HAS_BALANCE_ROWS' 'ROW_PRESENT'),
          (Row 'НФ-00000879' '0' 'NO_BALANCE_ROW' 'NO_BALANCE_ROW'))
}
$json=ConvertTo-NaturalStockJson $two
$obj=$ser.DeserializeObject($json)
Assert ($obj['status'] -ceq 'PASS') 'STATUS'
Assert ($obj['items'].Length -eq 2) 'TWO_ITEMS'
Assert ($obj['items'][0]['total_quantity'] -eq '6') 'FIRST_6'
Assert ($obj['items'][1]['total_quantity'] -eq '0') 'SECOND_0'
Assert ($obj['items'][1]['balance_state'] -eq 'NO_BALANCE_ROW') 'ROW_MISSING'
Assert (-not ($json -match '"guid"|Ref_Key|item_guid|warehouse_guid')) 'NO_GUIDS'
Assert ((ConvertTo-NaturalStockJson @{status='UNAVAILABLE'}) -ceq '{"status":"UNAVAILABLE"}') 'ERROR_STATUS'
$one=@{}+$two
$one['items']=@($two['items'][0]);$one['match_count']=1
Assert (($ser.DeserializeObject((ConvertTo-NaturalStockJson $one))['items'].Length) -eq 1) 'ONE_MATCH'
$ten=@{}+$two
$ten['items']=@()
for($i=1;$i -le 10;$i++) {
  $ten['items']+=@(Row ('НФ-'+$i.ToString('00000000')) ($i.ToString()) 'HAS_BALANCE_ROWS' 'ROW_PRESENT')
}
$ten['match_count']=10
Assert (($ser.DeserializeObject((ConvertTo-NaturalStockJson $ten))['items'].Length) -eq 10) 'TEN_MATCHES'
$special=@{}+$two
$special['items']=@($two['items'][0],$two['items'][1])
$special['items'][0]=@{}+$two['items'][0]
$special['items'][0]['name']='Товар "Ёж"\спец'
$special['items'][1]=@{}+$two['items'][1]
$special['items'][1]['code']='Код '+([string][char]10)+'строка'
$specialJson=ConvertTo-NaturalStockJson $special
$decoded=$ser.DeserializeObject($specialJson)
Assert ($decoded['items'][0]['name'] -ceq $special['items'][0]['name']) 'ESCAPED_QUOTE_AND_SLASH'
Assert ($decoded['items'][1]['code'] -ceq $special['items'][1]['code']) 'ESCAPED_CONTROL'
foreach($mutate in @('BAD_COUNT','BAD_TOTAL','BAD_MISSING_ROW','GUID_NAME')) {
  $doc=@{}+$two
  if($mutate -eq 'BAD_COUNT'){$doc['match_count']=3}
  elseif($mutate -eq 'BAD_TOTAL'){
    $doc['items']=@(@{}+$two['items'][0],$two['items'][1])
    $doc['items'][0]['total_quantity']='5'
  }
  elseif($mutate -eq 'BAD_MISSING_ROW'){
    $doc['items']=@($two['items'][0],@{}+$two['items'][1])
    $doc['items'][1]['warehouses']=@(@{name='Основной склад';quantity='1';balance_state='NO_BALANCE_ROW'})
  }
  else { $doc['items']=@(@{}+$two['items'][0],$two['items'][1]);$doc['items'][0]['name']='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
  $rejected=$false
  try{$null=ConvertTo-NaturalStockJson $doc}catch{$rejected=$true}
  Assert $rejected ('REJECT_'+$mutate)
}
'ONEC_POWERSHELL2_JSON_EMITTER_ONE_TWO_TEN=PASS'
'ONEC_POWERSHELL2_JSON_EMITTER_ESCAPE_AND_FAIL_CLOSED=PASS'

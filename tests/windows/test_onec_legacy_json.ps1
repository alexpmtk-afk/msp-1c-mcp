#requires -version 2
# Independently exercise the fallback JSON parser without ASP.NET assemblies.
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..')).Path
. (Join-Path $root 'scripts\windows\onec-legacy-json.ps1')
$ser=New-Object MspLegacyJson
$ser.MaxJsonLength=262144
function Assert([bool]$yes,[string]$label) { if (-not $yes) { throw ('JSON_TEST_FAIL_'+$label) } }
$inputJson='{"odata.metadata":"ignored","value":[{"Ref_Key":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","Description":"Слэмбол 6 кг","Code":"НФ-00001359","Артикул":""},{"Ref_Key":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","Description":"Слэмбол 6 кг","Code":"НФ-00000879","Артикул":null}]}'
$parsed=$ser.DeserializeObject($inputJson)
Assert ($parsed.ContainsKey('value')) 'ROOT'
$rows=@($parsed['value'])
Assert ($rows.Count -eq 2) 'CARD_COUNT'
Assert ($rows[0]['Description'] -ceq 'Слэмбол 6 кг') 'NAME'
Assert ($rows[0]['Code'] -ceq 'НФ-00001359') 'CODE'
Assert ($rows[0]['Артикул'] -ceq '') 'EMPTY_ARTICLE'
Assert ($null -eq $rows[1]['Артикул']) 'NULL_ARTICLE'
$balance='{"value":[{"Номенклатура_Key":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","СтруктурнаяЕдиница_Key":"cccccccc-cccc-cccc-cccc-cccccccccccc","КоличествоBalance":6.000}]}'
$b=$ser.DeserializeObject($balance)
Assert (@($b['value']).Count -eq 1) 'BALANCE_CARD'
Assert ([decimal]@($b['value'])[0]['КоличествоBalance'] -eq 6) 'DECIMAL'
$object=@{status='PASS';search_kind='name';search_term='Слэмбол 6 кг';requested_warehouse='Основной склад';match_count=2;items=@(
 @{name='Слэмбол 6 кг';article=$null;code='НФ-00001359';warehouses=@(@{name='Основной склад';quantity='6';balance_state='ROW_PRESENT'});total_quantity='6';balance_state='HAS_BALANCE_ROWS'},
 @{name='Слэмбол 6 кг';article=$null;code='НФ-00000879';warehouses=@(@{name='Основной склад';quantity='0';balance_state='NO_BALANCE_ROW'});total_quantity='0';balance_state='NO_BALANCE_ROW'}
);source='1C NewBase Balance';mode='read-only'}
$wire=$ser.Serialize($object)
$again=$ser.DeserializeObject($wire)
Assert ($again['status'] -eq 'PASS') 'ROUNDTRIP_STATUS'
Assert ($again['items'].Length -eq 2) 'ROUNDTRIP_COUNT'
Assert ($again['items'][0]['name'] -ceq 'Слэмбол 6 кг') 'ROUNDTRIP_UTF8'
$bad=@('{"a":1,"a":2}','{"value":[{"x":1},]}','{"value":"\uZZZZ"}','{"value":1}extra','{"a":[1,]}')
foreach($s in $bad) {
 $failed=$false
 try { $null=$ser.DeserializeObject($s) } catch { $failed=$true }
 Assert $failed 'REJECT_MALFORMED_JSON'
}
'ONEC_CLR2_JSON_ROUNDTRIP=PASS'
'ONEC_CLR2_JSON_NEGATIVE_CASES=PASS'

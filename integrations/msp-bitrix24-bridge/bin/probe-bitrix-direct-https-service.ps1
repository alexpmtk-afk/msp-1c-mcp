#requires -version 2
# One-shot LocalService transport-only check: SRV -> pinned Bitrix24 HTTPS.
# No credentials, REST API, customer export, or 1C calls.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$root='C:\ProgramData\MspCustomerStore'
$status=Join-Path $root 'state\bitrix-direct-https-smoke-status.txt'
function Fail([string]$Code){throw ('DIRECT_HTTPS_'+$Code)}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-19'){Fail 'LOCAL_SERVICE_REQUIRED'}
 if([IO.File]::Exists($status)){Fail 'ALREADY_TESTED'}
 $curl=Join-Path $root 'bin\curl.exe'
 $ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $worker=Join-Path $root 'bin\bitrix-search-outbound-once.ps1'
 $adapter=Join-Path $root 'bin\query-bitrix-search-index.ps1'
 $index=Join-Path $root 'state\bitrix-search-index-accepted.txt'
 $accept=Join-Path $root 'state\bitrix-json1-installed-runtime-status.txt'
 $db=Join-Path $root 'data\customers.db'
 $sqlite=Join-Path $root 'bin\sqlite3.exe'
 foreach($f in @($curl,$ca,$worker,$adapter,$index,$accept,$db,$sqlite)){
  if(-not [IO.File]::Exists($f)){Fail 'REQUIRED_COMPONENT_MISSING'}
  if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'REPARSE_COMPONENT'}
 }
 foreach($f in @((Join-Path $root 'config\bitrix-search-worker.ini'),(Join-Path $root 'secrets\bitrix-search-worker.dpapi'))){
  if([IO.File]::Exists($f)){Fail 'OLD_RELAY_WORKER_CONFIGURED'}
 }
 $accepted=[IO.File]::ReadAllText($accept,[Text.Encoding]::ASCII).Trim()
 if($accepted -notmatch '^UTC=[^;]+;STATUS=PASS;IDENTITY=LOCAL_SERVICE;INSTALLED_WORKER_SHA256=PASS;ROLLBACK_SHA256=PASS;ADAPTER_SHA256=PASS;PS2_PARSE=PASS;JSON1_CONTRACT=PASS;CUSTOMERS=6433;INDEX=6433;DB_INTEGRITY=ok;WORKER_ENABLED=NO;NETWORK_CALLS=0;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'PREVIOUS_ACCEPTANCE_INVALID'}
 $ir=[IO.File]::ReadAllText($index,[Text.Encoding]::ASCII).Trim()
 if($ir -notmatch ';STATUS=PASS;IDENTITY=LOCAL_SERVICE;SEARCH_INDEX=customer_search_v1;INDEXED=6433;CUSTOMERS=6433;DB_INTEGRITY=ok;ONEC_CALLS=0;BITRIX_CALLS=0$'){Fail 'INDEX_ACCEPTANCE_INVALID'}
 $phase='HTTPS_GET_NO_AUTH'
 $url='https://b24-uwmjda.bitrix24.ru/'
 $output=@(& $curl -q --silent --show-error --noproxy '*' --proto '=https' --tlsv1.2 --tls-max 1.2 --cacert $ca --max-redirs 0 --connect-timeout 10 --max-time 20 --output NUL --write-out 'HTTP=%{http_code};VERIFY=%{ssl_verify_result}' $url 2>&1)
 $ec=$LASTEXITCODE
 $result=($output -join '').Trim()
 if($ec -ne 0){Fail 'CURL_OR_TLS_FAILURE'}
 if($result -notmatch '^HTTP=([0-9]{3});VERIFY=([0-9]+)$'){Fail 'CURL_OUTPUT_INVALID'}
 $http=[int]$Matches[1]
 $verify=[int]$Matches[2]
 if($verify -ne 0){Fail 'TLS_CERTIFICATE_INVALID'}
 if($http -lt 200 -or $http -gt 599){Fail 'HTTP_NOT_RECEIVED'}
 $phase='DB_READONLY'
 $count=@(& $sqlite -readonly -batch -bail $db "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;" 2>&1)
 if($LASTEXITCODE -ne 0 -or ($count -join '').Trim() -ne '6433:6433'){Fail 'CUSTOMER_DB_CHANGED'}
 $idx=@(& $sqlite -readonly -batch -bail $db 'SELECT count(*) FROM customer_search_v1;' 2>&1)
 if($LASTEXITCODE -ne 0 -or ($idx -join '').Trim() -ne '6433'){Fail 'SEARCH_INDEX_CHANGED'}
 $phase='WRITE_RESULT'
 $msg='UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')+';STATUS=PASS;IDENTITY=LOCAL_SERVICE;TARGET=b24-uwmjda.bitrix24.ru;TLS_VERIFY=PASS;HTTP_STATUS='+$http+';CUSTOMERS=6433;INDEX=6433;WORKER_ENABLED=NO;REST_CALLS=0;ONEC_CALLS=0;CUSTOMER_EXPORT=0'
 $f=New-Object IO.FileStream -ArgumentList @($status,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$b=[Text.Encoding]::ASCII.GetBytes($msg);$f.Write($b,0,$b.Length);$f.Flush()}finally{$f.Close()}
 'DIRECT_BITRIX_TLS=PASS'
 'DIRECT_BITRIX_HTTP_STATUS='+$http
 'DIRECT_BITRIX_CERTIFICATE_VERIFIED=YES'
 'CUSTOMERS_AND_INDEX_UNCHANGED=6433'
 'WORKER_STILL_DISABLED=YES'
 'BITRIX_REST_CALLS=NO'
 'CUSTOMER_DATA_EXPORTED=NO'
 'ONEC_CALLS=NO'
 'RESULT=PASS;STAGE=SRV_BITRIX_DIRECT_HTTPS_LOCAL_SERVICE_PROBE'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^DIRECT_HTTPS_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 try{[IO.File]::WriteAllText($status,('STATUS=FAIL;GATE='+$gate+';PHASE='+$phase),[Text.Encoding]::ASCII)}catch{}
 'RESULT=FAIL;STAGE=SRV_BITRIX_DIRECT_HTTPS_LOCAL_SERVICE_PROBE;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}
#requires -version 2
# Guarded LocalService one-shot: 1 GET existing TEST NewBase order stock row, sanitized aggregate.
# Only stages new files/new task; preserves the V2 metadata receipt and all existing tasks.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore';$phase='PRECHECK'
function Fail([string]$Code){throw ('ONEC_HEADER_LAUNCH_'+$Code)}
function Need([bool]$Ok,[string]$Code){if(-not $Ok){Fail $Code}}
function Guard([string]$File){
 Need ([IO.File]::Exists($File)) 'FILE_MISSING'
 Need (([IO.File]::GetAttributes($File) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'REPARSE_DENIED'
}
function GitBlob([string]$Path){
 Guard $Path
 $b=[IO.File]::ReadAllBytes($Path)
 $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$b.Length+[char]0))
 $blob=New-Object byte[] ($header.Length+$b.Length)
 [Array]::Copy($header,0,$blob,0,$header.Length)
 [Array]::Copy($b,0,$blob,$header.Length,$b.Length)
 $sha=New-Object Security.Cryptography.SHA1Managed
 try{return ([BitConverter]::ToString($sha.ComputeHash($blob))).Replace('-','').ToLowerInvariant()}
 finally{$sha.Clear()}
}
try{
 Need ($ExpectedComputerName -eq 'SRV' -and $env:COMPUTERNAME -eq 'SRV') 'WRONG_HOST'
 Need ($PSVersionTable.PSVersion.Major -eq 2 -and [IntPtr]::Size -eq 8) 'PS2_X64_ONLY'
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 Need ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'ADMIN_REQUIRED'
 $cfg=Join-Path $root 'config\collector.ini';$secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 $v2=Join-Path $root 'state\bitrix-to-onec-customer-order-metadata-v2.txt'
 $state=Join-Path $root 'state\bitrix-to-onec-order-header-readonly-v1.txt'
 $folderName=Join-Path $root 'staging\bitrix-to-onec-order-header-v1'
 $worker=Join-Path $folderName 'probe-newbase-order-header-readonly-v1.ps1'
 foreach($file in @($cfg,$secret,$curl,$ca,$v2)){Guard $file}
 Need (-not [IO.File]::Exists($state)) 'RECEIPT_ALREADY_EXISTS'
 Need (-not [IO.Directory]::Exists($folderName)) 'STAGING_ALREADY_EXISTS'
 $flags=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
 foreach($f in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  Need ($flags -match ('(?m)^'+[regex]::Escape($f)+'\r?$')) 'LEGACY_FLAGS_CHANGED'
 }
 $metadata=[IO.File]::ReadAllText($v2,[Text.Encoding]::ASCII)
 foreach($mark in @('STATUS=PASS;SOURCE=TEST_NEWBASE;GET_ONLY=YES','ENTITY_SETS=1492','ROOT_ORDER_CANDIDATES=1','DOCUMENT_FIELDS=191','RELATED_PART_SETS=26','DETAILED_PRODUCT_PARTS=11','RESULT=PASS;STAGE=ONEC_CUSTOMER_ORDER_METADATA_READONLY_V2')){
  Need ($metadata.Contains($mark)) 'V2_METADATA_NOT_ACCEPTED'
 }
 $s=New-Object -ComObject Schedule.Service;$s.Connect()
 $folder=$s.GetFolder('\')
 $previous=$folder.GetTask('MspOnecCustomerOrderMetadataReadOnlyV2')
 Need ([int]$previous.State -eq 3 -and [int]$previous.LastTaskResult -eq 0 -and $previous.Definition.Triggers.Count -eq 0) 'V2_TASK_NOT_ACCEPTED'
 # Prerequisite: last OData row V2 completed read-only, no mutations.
 $rowStatus=Join-Path $root 'state\bitrix-to-onec-stock-row-readonly-v2.txt'
 Guard $rowStatus
 $rowText=[IO.File]::ReadAllText($rowStatus,[Text.Encoding]::ASCII)
 foreach($mark in @('SOURCE=TEST_NEWBASE;ODATA_GET=1;ONEC_WRITES=0;CRM_WRITES=0;RAW_DATA_EXPORTED=0','ROW_FOUND=YES','NOMENCLATURE_CLASS=GUID_TEXT','NOMENCLATURE_TYPE_FAMILY=CATALOG','NOMENCLATURE_TYPE_EXPECTED=YES','UNIT_TYPE_FAMILY=CATALOG','CHARACTERISTIC_GUID_STATE=ZERO_GUID','VAT_RATE_GUID_STATE=NONZERO_GUID','RESULT=PASS;STAGE=ONEC_STOCK_ROW_READONLY_V2')){
  Need ($rowText.Contains($mark)) 'ROW_V2_RECEIPT_NOT_ACCEPTED'
 }
 $priorRow=$folder.GetTask('MspOnecOrderStockRowReadOnlyV2')
 Need ([int]$priorRow.State -eq 3 -and [int]$priorRow.LastTaskResult -eq 0 -and $priorRow.Definition.Triggers.Count -eq 0) 'ROW_V2_TASK_NOT_ACCEPTED'
 'STOCK_ROW_V2=ACCEPTED;HEADER_READ_ONLY=YES'
 $taskName='MspOnecOrderHeaderReadOnlyV1'
 $existing=$null;try{$existing=$folder.GetTask($taskName)}catch{}
 Need ($null -eq $existing) 'TASK_ALREADY_EXISTS'
 'METADATA_V2=ACCEPTED;NO_SOURCE_CHANGES=YES'
 $phase='DOWNLOAD_PINNED_WORKER'
 [void][IO.Directory]::CreateDirectory($folderName)
 $url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/949ae87ed14d8688807efe112223a9cca90aa2e6/integrations/msp-bitrix24-bridge/bin/probe-newbase-order-header-readonly-v1.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --connect-timeout 10 --max-time 60 --output $worker $url
 Need ($LASTEXITCODE -eq 0) 'DOWNLOAD_FAILED'
 Need ((GitBlob $worker) -eq 'd8eef49555792c35279dcac7da6a01ce794829bc') 'WORKER_HASH_INVALID'
 $errs=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($worker,[Text.Encoding]::UTF8),[ref]$errs)
 Need ($null -eq $errs -or $errs.Count -eq 0) 'PS2_PARSE_INVALID'
 'WORKER=VERIFIED'
 $phase='REGISTER_ONE_SHOT'
 $svc=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$s.NewTask(0)
 $def.RegistrationInfo.Description='TEST NewBase read-only one order header sample, redacted; no triggers'
 $def.Principal.UserId=$svc;$def.Principal.LogonType=5;$def.Principal.RunLevel=0
 $def.Settings.Enabled=$true;$def.Settings.ExecutionTimeLimit='PT3M';$def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0);$action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -ExpectedComputerName SRV'
 $null=$folder.RegisterTaskDefinition($taskName,$def,2,$svc,$null,5,$null)
 $t=$folder.GetTask($taskName)
 Need ($t.Enabled -and $t.Definition.Triggers.Count -eq 0 -and [int]$t.Definition.Principal.LogonType -eq 5) 'TASK_DEFINITION_INVALID'
 $phase='START_ONCE'
 $null=$t.Run($null)
 'TASK=STARTED;TRIGGERS=0;IDENTITY=LOCAL_SERVICE'
 'RECEIPT_PATH='+$state
 'ONEC_REQUESTS=ONE_ORDER_HEADER_GET;ONEC_WRITES=0;CRM_WRITES=0;SQLITE_WRITES=0'
 'RESULT=STARTED;STAGE=ONEC_ORDER_HEADER_READONLY_V1'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^ONEC_HEADER_LAUNCH_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=ONEC_ORDER_HEADER_READONLY_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}

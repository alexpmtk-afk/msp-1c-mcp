#requires -version 2
# One-shot SAFE diagnostics only. No 1C/CRM writes; no customers.db writes.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$report=Join-Path $root 'state\msp-newbuyer-diagnostic-v1.status'
$phase='START'
$secretPlain=$null;$secretCipher=$null;$net=$null;$response=$null;$mutex=$null;$locked=$false
function Note([string]$Value){
 [IO.File]::AppendAllText($report,($Value+[Environment]::NewLine),[Text.Encoding]::ASCII)
}
function Gate([string]$Code){throw ('NEWBUYER_DIAG_'+$Code)}
function FileHash([string]$Path){
 $h=New-Object Security.Cryptography.SHA256Managed
 try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
 finally{$h.Clear()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Gate 'WRONG_HOST'}
 [IO.File]::WriteAllText($report,'STATUS=RUNNING;STAGE=NEWBUYER_DIAGNOSTIC_V1'+[Environment]::NewLine,[Text.Encoding]::ASCII)
 Note ('UTC='+[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
 Note ('PHASE='+$phase)
 $mutex=New-Object Threading.Mutex -ArgumentList @($false,'Global\MspNewBuyerDiagnosticV1')
 if(-not $mutex.WaitOne(0,$false)){Gate 'ALREADY_RUNNING'}
 $locked=$true
 $phase='IDENTITY'
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Gate 'PS2_X64_REQUIRED'}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if($identity.User.Value -ne 'S-1-5-19'){Gate 'LOCAL_SERVICE_REQUIRED'}
 Note 'IDENTITY=LOCAL_SERVICE;PS2_X64=PASS'
 $phase='OLD_TASK'
 $sched=New-Object -ComObject Schedule.Service
 $sched.Connect()
 $task=$sched.GetFolder('\').GetTask('MspNewBuyerDiscoveryV1')
 if($null -eq $task -or [int]$task.State -eq 4){Gate 'OLD_TASK_NOT_IDLE'}
 Note ('OLD_TASK_LAST_RESULT='+[int]$task.LastTaskResult)
 Note ('OLD_TASK_TRIGGERS='+[int]$task.Definition.Triggers.Count)
 $phase='WORKER_READ'
 $f=Join-Path $root 'staging\msp-newbuyer-discovery-v1\discover-newbase-new-buyers-v1.ps1'
 if(-not [IO.File]::Exists($f)){Gate 'OLD_WORKER_MISSING'}
 if(([IO.File]::GetAttributes($f) -band [IO.FileAttributes]::ReparsePoint) -ne 0){Gate 'OLD_WORKER_REPARSE'}
 $hash=FileHash $f
 if($hash -ne '6630af6daec00430d7587f51f26c5960f15dcc25aaf313ffc208cbfa7c13130f'){Gate 'OLD_WORKER_HASH_CHANGED'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($f,[Text.Encoding]::UTF8),[ref]$errors)
 if($errors -and $errors.Count -ne 0){Gate 'OLD_WORKER_SYNTAX_ERROR'}
 Note 'OLD_WORKER_READ=PASS;HASH=PASS;PS2_PARSE=PASS'
 $phase='SQLITE_READ'
 $exe=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 if(-not [IO.File]::Exists($exe) -or -not [IO.File]::Exists($db)){Gate 'SQLITE_MISSING'}
 $checks=@(& $exe -readonly -batch -bail $db "SELECT 'MAP='||count(*)||':'||count(DISTINCT onec_guid)||':'||(SELECT count(*) FROM (SELECT entity_kind,crm_id FROM msp_initial_map GROUP BY entity_kind,crm_id)) FROM msp_initial_map;SELECT 'CUSTOMERS='||count(*) FROM customers;SELECT 'QUEUE_TABLE='||count(*) FROM sqlite_master WHERE type='table' AND name='msp_newbuyer_queue';PRAGMA quick_check;")
 if($LASTEXITCODE -ne 0 -or $checks.Count -lt 4){Gate 'SQLITE_READ_ERROR'}
 if($checks[0] -ne 'MAP=6433:6433:6433' -or $checks[3] -ne 'ok'){Gate 'SQLITE_INVARIANTS_CHANGED'}
 foreach($line in $checks){if($line -match '^(MAP|CUSTOMERS|QUEUE_TABLE)=[0-9:]+$' -or $line -eq 'ok'){Note ('SQLITE_'+$line)}else{Gate 'SQLITE_OUTPUT_UNEXPECTED'}}
 $phase='CONFIG'
 $cfg=Join-Path $root 'config\collector.ini'
 if(-not [IO.File]::Exists($cfg)){Gate 'CONFIG_MISSING'}
 $flags=[IO.File]::ReadAllText($cfg,[Text.Encoding]::ASCII)
 foreach($flag in @('ACTIVE=0','ONEC_READ=0','DELTA_READ=0','BITRIX=0')){
  if($flags -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Gate 'COLLECTOR_NOT_SAFE_IDLE'}
 }
 Note 'COLLECTOR_SAFE_IDLE=PASS'
 $phase='ODATA_AUTH'
 $secret=Join-Path $root 'secrets\onec-test-odata.dpapi'
 if(-not [IO.File]::Exists($secret)){Gate 'ODATA_SECRET_MISSING'}
 Add-Type -AssemblyName System.Security
 $secretCipher=[IO.File]::ReadAllBytes($secret)
 if($secretCipher.Length -lt 32 -or $secretCipher.Length -gt 8192){Gate 'ODATA_CIPHER_SIZE'}
 $entropy=[Text.Encoding]::ASCII.GetBytes('MspCustomerStore-OnecTest-OData-v1')
 $secretPlain=[Security.Cryptography.ProtectedData]::Unprotect($secretCipher,$entropy,[Security.Cryptography.DataProtectionScope]::LocalMachine)
 if($secretPlain.Length -lt 2 -or $secretPlain.Length -gt 1024 -or $secretPlain.Length%2 -ne 0){Gate 'ODATA_DECRYPT_SIZE'}
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $secretPlain.Length;$i+=2){$secure.AppendChar([char][BitConverter]::ToUInt16($secretPlain,$i))}
 $secure.MakeReadOnly()
 [Array]::Clear($secretPlain,0,$secretPlain.Length);$secretPlain=$null
 $cred=New-Object Management.Automation.PSCredential -ArgumentList @('MCP_OData_ReadOnly',$secure)
 Note 'ODATA_DPAPI=PASS'
 $phase='ODATA_COUNT_ONLY'
 $entity=[regex]::Unescape('\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442\u044b')
 $buyer=[regex]::Unescape('\u041f\u043e\u043a\u0443\u043f\u0430\u0442\u0435\u043b\u044c')
 $invalid=[regex]::Unescape('\u041d\u0435\u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0442\u0435\u043b\u0435\u043d')
 $filter=$buyer+' eq true and DeletionMark eq false and '+$invalid+' eq false'
 $uri='http://127.0.0.1:8085/NewBase/odata/standard.odata/Catalog_'+$entity+'/$count?$filter='+[Uri]::EscapeDataString($filter)
 $request=[Net.HttpWebRequest][Net.WebRequest]::Create($uri)
 $request.Method='GET';$request.Accept='application/atom+xml';$request.Proxy=$null
 $request.AllowAutoRedirect=$false
 $request.Credentials=$cred.GetNetworkCredential();$request.PreAuthenticate=$true
 $request.Timeout=20000;$request.ReadWriteTimeout=20000
 try{
  $response=$request.GetResponse()
  if([int]$response.StatusCode -ne 200){Gate 'ODATA_COUNT_NOT_200'}
  $reader=New-Object IO.StreamReader -ArgumentList @($response.GetResponseStream(),[Text.Encoding]::ASCII)
  try{
   $count=$reader.ReadToEnd().Trim()
   if($count -notmatch '^[0-9]{1,8}$'){Gate 'ODATA_COUNT_BAD_BODY'}
   Note ('ODATA_ACTIVE_BUYER_COUNT='+$count)
  }finally{$reader.Close()}
 }catch [Net.WebException]{
  $code='NONE'
  if($null -ne $_.Exception.Response){
   $code=[string][int]([Net.HttpWebResponse]$_.Exception.Response).StatusCode
  }
  Note ('ODATA_WEB_STATUS='+([string]$_.Exception.Status))
  Note ('ODATA_HTTP_STATUS='+$code)
  Gate 'ODATA_COUNT_WEB_EXCEPTION'
 }finally{if($null -ne $response){$response.Close();$response=$null}}
 $phase='FINAL'
 Note 'RESULT=PASS;STAGE=MSP_NEWBUYER_DIAGNOSTIC_V1;ONEC_WRITES=0;CRM_WRITES=0;SQLITE_WRITES=0;AUTO_UPDATE=OFF'
 'RESULT=PASS;STAGE=MSP_NEWBUYER_DIAGNOSTIC_V1'
}catch{
 $name=$_.Exception.GetType().Name
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^NEWBUYER_DIAG_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 $line=[int]$_.InvocationInfo.ScriptLineNumber
 try{Note ('RESULT=FAIL;STAGE=MSP_NEWBUYER_DIAGNOSTIC_V1;PHASE='+$phase+';GATE='+$gate+';EXCEPTION_TYPE='+$name+';LINE='+$line+';ONEC_WRITES=0;CRM_WRITES=0;SQLITE_WRITES=0;AUTO_UPDATE=OFF')}catch{}
 'RESULT=FAIL;STAGE=MSP_NEWBUYER_DIAGNOSTIC_V1;PHASE='+$phase+';GATE='+$gate
 exit 1
}finally{
 if($locked){$mutex.ReleaseMutex()}
 if($null -ne $mutex){$mutex.Close()}
 if($null -ne $secretPlain){[Array]::Clear($secretPlain,0,$secretPlain.Length)}
 if($null -ne $secretCipher){[Array]::Clear($secretCipher,0,$secretCipher.Length)}
 if($null -ne $secure){$secure.Dispose()}
 $cred=$null;$net=$null;$request=$null
}

#requires -version 2
# One-time read-only TEST NewBase/Bitrix24 inflight audit; zero schedule triggers.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$phase='PRECHECK'
function Fail([string]$code){throw ('AUDIT_START_'+$code)}
function Sha([string]$path){$h=New-Object Security.Cryptography.SHA256Managed;try{return ([BitConverter]::ToString($h.ComputeHash([IO.File]::ReadAllBytes($path)))).Replace('-','').ToLowerInvariant()}finally{$h.Clear()}}
function Checked([string]$path,[string]$expect){
 if(-not [IO.File]::Exists($path)){Fail 'STAGED_FILE_MISSING'}
 if((Sha $path) -ne $expect){Fail 'STAGED_HASH_MISMATCH'}
 $errors=$null
 $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($path,[Text.Encoding]::ASCII),[ref]$errors)
 if($errors -and $errors.Count -gt 0){Fail 'STAGED_PARSE_FAILED'}
}
try{
 if($ExpectedComputerName -ne 'SRV' -or $env:COMPUTERNAME -ne 'SRV'){Fail 'HOST_INVALID'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $user=[Security.Principal.WindowsIdentity]::GetCurrent()
 $admin=New-Object Security.Principal.WindowsPrincipal -ArgumentList $user
 if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Fail 'ADMIN_REQUIRED'}
 $v2=Join-Path $root 'state\bitrix-initial-all-buyers-v2.status'
 if(-not [IO.File]::Exists($v2)){Fail 'V2_STATUS_MISSING'}
 $text=[IO.File]::ReadAllText($v2,[Text.Encoding]::ASCII)
 if($text -notmatch 'STATUS=FAIL;GATE=CRM_DETAILS_BACKREAD_MISMATCH;PHASE=CRM_CREATE_BACKREAD;' -or $text -notmatch ';MAPPED=5;TARGET=6433'){Fail 'V2_STATUS_UNEXPECTED'}
 $sqlite=Join-Path $root 'bin\sqlite3.exe';$db=Join-Path $root 'data\customers.db'
 if(-not [IO.File]::Exists($sqlite) -or -not [IO.File]::Exists($db)){Fail 'SQLITE_MISSING'}
 $count=@(& $sqlite -readonly -batch -bail $db "SELECT (SELECT count(*) FROM msp_initial_map)||':'||(SELECT count(*) FROM msp_initial_inflight);" 2>&1)
 if($LASTEXITCODE -ne 0 -or ($count -join '').Trim() -notmatch '^5:([1-9]|1[0-9]|20)$'){Fail 'UNEXPECTED_INFLIGHT_COUNTS'}
 $sch=New-Object -ComObject Schedule.Service
 $sch.Connect()
 $folder=$sch.GetFolder('\')
 $old=$folder.GetTask('MspNewBaseInitialImportV2')
 if($null -eq $old -or [int]$old.State -eq 4 -or $old.Definition.Triggers.Count -ne 0){Fail 'OLD_IMPORT_NOT_IDLE'}
 $name='MspNewBaseInflightAuditV1'
 $found=$null;try{$found=$folder.GetTask($name)}catch{}
 if($null -ne $found){Fail 'AUDIT_TASK_ALREADY_PRESENT'}
 $report=Join-Path $root 'state\bitrix-initial-inflight-readonly-v1.status'
 if([IO.File]::Exists($report)){Fail 'AUDIT_REPORT_ALREADY_EXISTS'}
 $staging=Join-Path $root 'staging\bitrix-inflight-audit-v1'
 if([IO.Directory]::Exists($staging)){Fail 'STAGING_ALREADY_EXISTS'}
 $curl=Join-Path $root 'bin\curl.exe';$ca=Join-Path $root 'config\curl-ca-bundle.crt'
 foreach($file in @($curl,$ca)){
  if(-not [IO.File]::Exists($file)){Fail 'DEPENDENCY_MISSING'}
 }
 $phase='STAGE_READONLY_AUDIT'
 [void][IO.Directory]::CreateDirectory($staging)
 $base='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/e08280c726b4aab1b0108d3bfa8bc4ee3d406911/integrations/msp-bitrix24-bridge/bin/'
 $worker=Join-Path $staging 'audit-initial-buyer-inflight-v1.ps1'
 $core=Join-Path $staging 'msp-newbase-bitrix-core-v2.ps1'
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $worker ($base+'audit-initial-buyer-inflight-v1.ps1')
 if($LASTEXITCODE -ne 0){Fail 'AUDIT_DOWNLOAD_FAILED'}
 & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --output $core ($base+'msp-newbase-bitrix-core-v2.ps1')
 if($LASTEXITCODE -ne 0){Fail 'CORE_DOWNLOAD_FAILED'}
 Checked $worker 'bb96d148f261e7180706851bea1d21f29041dcd0128ff887afdd68e81257feb4'
 Checked $core '6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852'
 'INFLIGHT_AUDIT_BOTH_HASHES=PASS'
 $phase='CREATE_READONLY_TASK'
 $svc=(New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19').Translate([Security.Principal.NTAccount]).Value
 $def=$sch.NewTask(0)
 $def.RegistrationInfo.Description='One-time read-only count/identity diagnostic of initial TEST buyers inflight'
 $def.Principal.UserId=$svc
 $def.Principal.LogonType=5
 $def.Principal.RunLevel=0
 $def.Settings.Enabled=$true
 $def.Settings.ExecutionTimeLimit='PT15M'
 $def.Settings.MultipleInstances=2
 $action=$def.Actions.Create(0)
 $action.Path=Join-Path $PSHOME 'powershell.exe'
 $action.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'"'
 $null=$folder.RegisterTaskDefinition($name,$def,2,$svc,$null,5,$null)
 $task=$folder.GetTask($name)
 if($task.Definition.Triggers.Count -ne 0){Fail 'UNEXPECTED_AUTO_TRIGGERS'}
 $phase='RUN_READONLY_ONCE'
 $null=$task.Run($null)
 'READONLY_AUDIT_TASK=STARTED'
 'OLD_IMPORT=UNCHANGED'
 'CRM_WRITES=NO'
 'SQLITE_WRITES=NO'
 'ONEC_REQUESTS=NO'
 'REPORT='+$report
 'RESULT=PASS;STAGE=INITIAL_INFLIGHT_READONLY_AUDIT_STARTED'
}catch{
 $gate='UNCLASSIFIED'
 if($_.Exception.Message -match '^AUDIT_START_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=INITIAL_INFLIGHT_READONLY_AUDIT_STARTED;GATE='+$gate+';PHASE='+$phase
 'NO_RETRY=YES'
 exit 1
}

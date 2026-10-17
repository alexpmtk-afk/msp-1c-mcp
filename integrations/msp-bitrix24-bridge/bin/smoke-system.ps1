#requires -version 2
# Execute the newly staged task manually; verify fresh LOCAL SERVICE SAFE_IDLE heartbeat.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
function Fail([string]$Reason){Write-Output ('RESULT=FAIL;STAGE=BITRIX24_SMOKE;GATE='+$Reason);exit 1}
try{
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  $s=New-Object -ComObject Schedule.Service;$s.Connect()
  $t=$s.GetFolder('\').GetTask('MspBitrix24Bridge')
  $sid=(New-Object Security.Principal.NTAccount -ArgumentList @($t.Definition.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
  if($sid -ne 'S-1-5-19'){Fail 'WRONG_IDENTITY'}
  if(-not $t.Enabled){Fail 'TASK_DISABLED'}
  if($t.Definition.Triggers.Item(1).Enabled -or $t.Definition.Triggers.Item(2).Enabled){Fail 'AUTOSTART_PREMATURE'}
  $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'MspBitrix24Bridge'
  $status=Join-Path $root 'state\status.txt'
  $start=[DateTime]::UtcNow
  $null=$t.Run($null)
  $ok=$false
  for($i=0;$i -lt 30;$i++){
    Start-Sleep -Seconds 2
    if(-not (Test-Path -LiteralPath $status -PathType Leaf)){continue}
    $val=[IO.File]::ReadAllText($status,[Text.Encoding]::ASCII).Trim()
    if($val -match '^UTC=([^;]+);STATUS=SAFE_IDLE;IDENTITY=LOCAL_SERVICE;CUSTOMERS_SYNC=OFF;WRITES=OFF$'){
      $when=[DateTime]::Parse($Matches[1]).ToUniversalTime()
      if($when -ge $start.AddSeconds(-2) -and $when -le [DateTime]::UtcNow.AddSeconds(2)){$ok=$true;break}
    }
  }
  if(-not $ok){Fail 'FRESH_SYSTEM_HEARTBEAT_MISSING'}
  'LOCAL_SERVICE_RUNTIME=PASS'
  'MANUAL_START=PASS'
  'AUTOMATIC_TRIGGERS=OFF'
  'CUSTOMERS_SYNC=OFF'
  'ONEC_WRITES=OFF'
  'RESULT=PASS;STAGE=BITRIX24_SMOKE'
}catch{Fail 'TASK_RUNTIME_ERROR'}

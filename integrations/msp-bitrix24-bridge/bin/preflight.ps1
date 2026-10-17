#requires -version 2
# Read-only system readiness check; must run locally on physical SRV.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
try {
  $scheduler=New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $folder=$scheduler.GetFolder('\')
  $hostok=($env:COMPUTERNAME -eq $ExpectedComputerName)
  $psok=($PSVersionTable.PSVersion.Major -eq 2)
  $os=Get-WmiObject Win32_OperatingSystem
  $winok=($os.Version -like '6.1.*')
  $sid=New-Object Security.Principal.SecurityIdentifier -ArgumentList @('S-1-5-19')
  $svc=$sid.Translate([Security.Principal.NTAccount]).Value
  $task='ABSENT'
  try { $null=$folder.GetTask('MspBitrix24Bridge');$task='PRESENT' } catch {}
  'MACHINE_MATCH='+$hostok
  'POWERSHELL_2='+$psok
  'WINDOWS_2008_R2='+$winok
  'LOCAL_SERVICE_AVAILABLE='+[bool]($svc)
  'BRIDGE_TASK='+$task
  'NO_LOCAL_CHANGES=YES'
  if ($hostok -and $psok -and $winok -and $svc -and $task -eq 'ABSENT') {
    'RESULT=PASS;STAGE=BITRIX24_PREFLIGHT'
  } else { 'RESULT=FAIL;STAGE=BITRIX24_PREFLIGHT' }
} catch {
  'RESULT=FAIL;STAGE=BITRIX24_PREFLIGHT;ERROR=LOCAL_CHECK_FAILED'
}

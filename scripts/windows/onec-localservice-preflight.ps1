#requires -version 2
# Windows Server 2008 R2 read-only readiness check for an independent LocalService agent.
# NEVER installs a task, changes privileges, reads credentials, or modifies 1C.
param([string]$ExpectedComputerName = 'SRV')
$ErrorActionPreference = 'Stop'
function Flag([bool]$ok) { if ($ok) { 'YES' } else { 'NO' } }
try {
  $machineOK = ($env:COMPUTERNAME -eq $ExpectedComputerName)
  $ps2 = ($PSVersionTable.PSVersion.Major -eq 2)
  $os = [Environment]::OSVersion.Version
  $win2008R2 = ($os.Major -eq 6 -and $os.Minor -eq 1)
  $p = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
  $programData = [IO.Directory]::Exists($p)
  $windows = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object System.Security.Principal.WindowsPrincipal -ArgumentList $windows
  $admin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

  $localServiceResolvable = $false
  try {
    $sid = New-Object Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-19'
    $name = $sid.Translate([Security.Principal.NTAccount])
    $localServiceResolvable = ($null -ne $name -and $name.Value.Length -gt 0)
  } catch {}

  $machineDpapi = $false
  try {
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $machineDpapi = ($null -ne [Security.Cryptography.ProtectedData] -and
      $null -ne [Security.Cryptography.DataProtectionScope])
  } catch {}

  $schedulerReady = $false
  $oldTask = 'UNKNOWN'
  try {
    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $folder = $svc.GetFolder('\')
    $schedulerReady = ($null -ne $folder)
    try {
      $task = $folder.GetTask('MspOnecHttpsAgentProbe')
      if ($null -ne $task) { $oldTask='PRESENT' }
    } catch {
      $oldTask='NOT_FOUND_OR_NOT_READABLE'
    }
  } catch {}

  Write-Output 'ONEC_LOCAL_SERVICE_MIGRATION_PREFLIGHT'
  Write-Output ('EXPECTED_MACHINE='+ (Flag $machineOK))
  Write-Output ('POWERSHELL_2='+ (Flag $ps2))
  Write-Output ('WINDOWS_SERVER_2008_R2_VERSION='+ (Flag $win2008R2))
  Write-Output ('PROGRAMDATA_PRESENT='+ (Flag $programData))
  Write-Output ('LOCAL_SERVICE_ACCOUNT_RESOLVES='+ (Flag $localServiceResolvable))
  Write-Output ('MACHINE_DPAPI_TYPE_AVAILABLE='+ (Flag $machineDpapi))
  Write-Output ('SCHEDULER_COM_READABLE='+ (Flag $schedulerReady))
  Write-Output ('CURRENT_PROCESS_ADMIN='+ (Flag $admin))
  Write-Output ('LEGACY_PERSONAL_AGENT_TASK='+$oldTask)
  Write-Output 'READ_ONLY=YES'
  if ($machineOK -and $ps2 -and $win2008R2 -and $programData -and
      $localServiceResolvable -and $machineDpapi -and $schedulerReady) {
    Write-Output 'RESULT=PASS'
    if (-not $admin) {
      Write-Output 'NEXT_GATE=ADMINISTRATIVE_INSTALLATION_REQUIRED'
    } else {
      Write-Output 'NEXT_GATE=ADMINISTRATIVE_INSTALLATION_POSSIBLE'
    }
  } else {
    Write-Output 'RESULT=NEEDS_REVIEW'
  }
} catch {
  Write-Output 'RESULT=FAIL;GATE=WINDOWS_READ_ONLY_PREFLIGHT'
  exit 1
}

#requires -version 2
# SRV-only SQLite runtime inventory; read-only, no executable loaded or executed.
# Works under native Windows PowerShell 2.0, ASCII-only source.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
function Fail([string]$Reason){throw ('STORAGE_'+$Reason)}
try {
  if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
  if($PSVersionTable.PSVersion.Major -ne 2){Fail 'PS_VERSION_UNEXPECTED'}
  $bridge='C:\ProgramData\MspBitrix24Bridge'
  $cfg=Join-Path $bridge 'config\bridge.ini'
  if(-not [IO.File]::Exists($cfg)){Fail 'BRIDGE_CONFIG_MISSING'}
  $text=[IO.File]::ReadAllText($cfg)
  foreach($flag in @('ACTIVE=0','CUSTOMERS_READ=0','PRODUCTS_READ=0','INVOICES_WRITE=0')){
    if($text -notmatch ('(?m)^'+[regex]::Escape($flag)+'\s*$')){Fail 'SAFE_IDLE_NOT_CONFIRMED'}
  }
  $os=Get-WmiObject Win32_OperatingSystem
  $osMajor=$os.Version
  'SRV_HOST='+$env:COMPUTERNAME
  'OS_VERSION='+$osMajor
  'OS_ARCHITECTURE='+$os.OSArchitecture
  'POWERSHELL_VERSION='+$PSVersionTable.PSVersion.ToString()
  'PROCESS_BITS='+([IntPtr]::Size*8)
  'CLR_VERSION='+[Environment]::Version.ToString()
  $net20=(Test-Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v2.0.50727')
  $net35=(Test-Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5')
  $net40=(Test-Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full')
  'NET20_REGISTRY='+$net20
  'NET35_REGISTRY='+$net35
  'NET4_FULL_REGISTRY='+$net40
  $disk=Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
  if($null -eq $disk){Fail 'DISK_INVENTORY_UNAVAILABLE'}
  'C_FREE_GIB='+[Math]::Round(([double]$disk.FreeSpace/1073741824),2)
  $cli=Join-Path $bridge 'bin\sqlite3.exe'
  $dll=Join-Path $bridge 'bin\System.Data.SQLite.dll'
  'BRIDGE_SQLITE_CLI_PRESENT='+[IO.File]::Exists($cli)
  'BRIDGE_SQLITE_PROVIDER_PRESENT='+[IO.File]::Exists($dll)
  $command=Get-Command sqlite3.exe -ErrorAction SilentlyContinue
  'SYSTEM_SQLITE_COMMAND_PRESENT='+($null -ne $command)
  if($null -ne $command){
    $location=$command.Definition
    $isBridge=($location.StartsWith($bridge,[StringComparison]::OrdinalIgnoreCase))
    'SYSTEM_SQLITE_COMMAND_IN_BRIDGE='+$isBridge
  }
  $sqliteNativeSystem=[IO.File]::Exists((Join-Path $env:windir 'System32\sqlite3.dll'))
  'SYSTEM_SQLITE_NATIVE_DLL='+$sqliteNativeSystem
  $data=Join-Path $bridge 'data\customers.db'
  'CUSTOMER_DB_ALREADY_EXISTS='+[IO.File]::Exists($data)
  'SAFE_IDLE=YES'
  'PROVIDER_COMPATIBILITY=NOT_YET_TESTED'
  'EXISTING_SQLITE_BINARY_EXECUTED=NO'
  'FILES_CREATED=NO'
  'DATA_WRITES=NO'
  'RESULT=PASS;STAGE=SRV_STORAGE_RUNTIME_INVENTORY'
}catch{
  $message=$_.Exception.Message
  $gate='STORAGE_RUNTIME_ERROR'
  if($message -match '^STORAGE_([A-Z_]+)$'){$gate=$Matches[1]}
  'RESULT=FAIL;STAGE=SRV_STORAGE_RUNTIME_INVENTORY;GATE='+$gate
}

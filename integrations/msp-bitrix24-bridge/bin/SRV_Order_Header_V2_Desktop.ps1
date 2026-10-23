#requires -version 2
# Starts the pinned GitHub V2 read-only launcher once and exports a sanitized TXT to the user's desktop.
# Windows Server 2008 R2, Windows PowerShell 2.0, elevated 64-bit shell.
# 1C: one GET of one non-deleted TEST NewBase customer order; zero 1C/CRM writes.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$phase='PRECHECK'
$desktop='C:\Users\parshin\Desktop'
$dest=Join-Path $desktop 'bitrix-to-onec-order-header-readonly-v2.txt'
$state='C:\ProgramData\MspCustomerStore\state\bitrix-to-onec-order-header-readonly-v2.txt'
$root='C:\ProgramData\MspCustomerStore'
$curl=Join-Path $root 'bin\curl.exe'
$ca=Join-Path $root 'config\curl-ca-bundle.crt'
$download=Join-Path $env:TEMP ('msp-order-header-v2-launcher-'+$PID+'.ps1')
$expectedBlob='34bd89ac2717d0a1135438572e6c529057cf9e29'
$url='https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/a170dbd4cbc413557d7c48775fb6a8fbe57cddbf/integrations/msp-bitrix24-bridge/bin/start-newbase-order-header-readonly-v2.ps1'
function GitBlob([string]$path){
 $bytes=[IO.File]::ReadAllBytes($path)
 $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$bytes.Length+[char]0))
 $inputBytes=New-Object byte[] ($header.Length+$bytes.Length)
 [Array]::Copy($header,0,$inputBytes,0,$header.Length)
 [Array]::Copy($bytes,0,$inputBytes,$header.Length,$bytes.Length)
 $sha=New-Object Security.Cryptography.SHA1Managed
 try {return ([BitConverter]::ToString($sha.ComputeHash($inputBytes))).Replace('-','').ToLowerInvariant()}
 finally {$sha.Clear()}
}
function SaveFail([string]$code){
 $body='RESULT=FAIL;STAGE=ONEC_ORDER_HEADER_READONLY_V2;PHASE='+$phase+';GATE='+$code+[Environment]::NewLine+'ONEC_WRITES=0;CRM_WRITES=0'+[Environment]::NewLine
 try{if([IO.Directory]::Exists($desktop) -and -not [IO.File]::Exists($dest)){[IO.File]::WriteAllText($dest,$body,[Text.Encoding]::UTF8)}}catch{}
 Write-Output $body
}
try {
 if($ExpectedComputerName -ne 'SRV' -or $env:COMPUTERNAME -ne 'SRV'){throw 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){throw 'PS2_X64_REQUIRED'}
 $principal=New-Object Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'ADMIN_REQUIRED'}
 if(-not [IO.Directory]::Exists($desktop)){throw 'DESKTOP_NOT_FOUND'}
 if([IO.File]::Exists($dest)){throw 'DESKTOP_REPORT_ALREADY_EXISTS'}
 # A previous completed V2 check is exported without triggering a second OData query.
 if(-not [IO.File]::Exists($state)){
  $phase='FETCH_PINNED_LAUNCHER'
  if(-not [IO.File]::Exists($curl) -or -not [IO.File]::Exists($ca)){throw 'CURL_OR_CA_MISSING'}
  & $curl -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --cacert $ca --proto '=https' --max-redirs 0 --connect-timeout 10 --max-time 60 --output $download $url
  if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($download)){throw 'DOWNLOAD_FAILED'}
  if((GitBlob $download) -ne $expectedBlob){throw 'LAUNCHER_HASH_INVALID'}
  $parseErrors=$null
  $null=[Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($download,[Text.Encoding]::UTF8),[ref]$parseErrors)
  if($null -ne $parseErrors -and $parseErrors.Count -gt 0){throw 'LAUNCHER_PS2_PARSE_INVALID'}
  $phase='RUN_ONE_SHOT'
  # Launcher registers and starts only one LocalService task with no timer.
  & "$PSHOME\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $download -ExpectedComputerName SRV
  if($LASTEXITCODE -ne 0){throw 'ONE_SHOT_LAUNCH_FAILED'}
  $phase='WAIT_FOR_RESULT'
  $deadline=[DateTime]::Now.AddSeconds(195)
  while((-not [IO.File]::Exists($state)) -and [DateTime]::Now -lt $deadline){Start-Sleep -Seconds 3}
  if(-not [IO.File]::Exists($state)){throw 'NO_RECEIPT_WITHIN_WAIT'}
 }
 $phase='COPY_SANITIZED_RECEIPT'
 $copied=$false
 for($i=0;$i -lt 7;$i++){
  try{
   # LocalService keeps its internal receipt for audit; user receives a separate desktop copy.
   [IO.File]::Copy($state,$dest,$false)
   $copied=$true
   break
  }catch{
   if([IO.File]::Exists($dest)){throw 'DESKTOP_COPY_FAILED'}
   Start-Sleep -Seconds 2
  }
 }
 if(-not $copied){throw 'DESKTOP_COPY_FAILED'}
 'DESKTOP_TXT='+$dest
 'RESULT=EXPORTED;READ_ONLY=YES'
 Get-Content $dest
}catch{
 $code=$_.Exception.Message
 if($code -notmatch '^[A-Z0-9_]+$'){$code='RUNTIME_ERROR'}
 SaveFail $code
 exit 1
}finally{
 if([IO.File]::Exists($download)){try{[IO.File]::Delete($download)}catch{}}
}

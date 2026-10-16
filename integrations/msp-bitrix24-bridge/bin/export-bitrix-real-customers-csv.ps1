#requires -version 2
# Prepare two local Bitrix24 CSV imports. No network, no 1C/CRM writes, no customer data in stdout.
param([string]$ExpectedComputerName='SRV')
$ErrorActionPreference='Stop'
$root='C:\ProgramData\MspCustomerStore'
$phase='PRECHECK'
function Fail([string]$Reason){throw ('CSV_'+$Reason)}
function CsvOut([string]$Db,[string]$Query,[string]$Path){
 $p=New-Object Diagnostics.Process
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=Join-Path $script:root 'bin\sqlite3.exe'
 $info.Arguments='-readonly -batch -bail -csv -header "'+$Db+'"'
 $info.UseShellExecute=$false
 $info.CreateNoWindow=$true
 $info.RedirectStandardInput=$true
 $info.RedirectStandardOutput=$true
 $info.RedirectStandardError=$true
 $p.StartInfo=$info
 try{
  if(-not $p.Start()){Fail 'SQL_START'}
  $p.StandardInput.WriteLine($Query);$p.StandardInput.Close()
  # sqlite3 emits UTF8 bytes; never decode through the Windows OEM console code page.
  $fs=New-Object IO.FileStream -ArgumentList @($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
   $bom=New-Object byte[] 3;$bom[0]=239;$bom[1]=187;$bom[2]=191;$fs.Write($bom,0,3)
   $buf=New-Object byte[] 8192;$size=0
   do{
    $n=$p.StandardOutput.BaseStream.Read($buf,0,$buf.Length)
    if($n -gt 0){$size+=$n;if($size -gt 4000000){Fail 'SQL_OUTPUT_TOO_LARGE'};$fs.Write($buf,0,$n)}
   }while($n -gt 0)
   $fs.Flush()
  }finally{$fs.Close()}
  $err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(30000)){$p.Kill();Fail 'SQL_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -ne 0 -or $size -lt 40){Fail 'SQL_OUTPUT_INVALID'}
 }finally{$p.Close()}
}
function Count([string]$Db,[string]$Sql){
 $p=New-Object Diagnostics.Process
 $i=New-Object Diagnostics.ProcessStartInfo
 $i.FileName=Join-Path $script:root 'bin\sqlite3.exe'
 $i.Arguments='-readonly -batch -bail "'+$Db+'"'
 $i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardInput=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
 $p.StartInfo=$i
 try{
  if(-not $p.Start()){Fail 'COUNT_START'}
  $p.StandardInput.WriteLine($Sql);$p.StandardInput.Close()
  $s=$p.StandardOutput.ReadToEnd().Trim();$err=$p.StandardError.ReadToEnd()
  if(-not $p.WaitForExit(20000)){$p.Kill();Fail 'COUNT_TIMEOUT'}
  if($p.ExitCode -ne 0 -or $err.Trim().Length -gt 0){Fail 'COUNT_ERROR'}
  return $s
 }finally{$p.Close()}
}
try{
 if($env:COMPUTERNAME -ne $ExpectedComputerName){Fail 'WRONG_HOST'}
 if($PSVersionTable.PSVersion.Major -ne 2 -or [IntPtr]::Size -ne 8){Fail 'PS2_X64_REQUIRED'}
 $db=Join-Path $root 'data\customers.db'
 $folder=Join-Path $root 'staging\bitrix-client-csv'
 if(-not [IO.File]::Exists($db)){Fail 'SOURCE_MISSING'}
 if([IO.Directory]::Exists($folder)){Fail 'PREVIOUS_EXPORT_DIAGNOSE_FIRST'}
 $expected=Count $db "SELECT count(*)||'|'||sum(onec_type='LEGAL')||'|'||sum(onec_type='PERSON')||'|'||sum(onec_type='REVIEW') FROM customers WHERE buyer=1 AND deletion_mark=0 AND invalid=0;"
 if($expected -ne '6433|1941|4486|6'){Fail 'SOURCE_BASELINE_CHANGED'}
 if((Count $db 'PRAGMA quick_check;') -ne 'ok'){Fail 'DB_INTEGRITY_FAILED'}
 [void][IO.Directory]::CreateDirectory($folder)
 $a=[IO.Directory]::GetAccessControl($folder)
 $a.SetAccessRuleProtection($true,$false)
 $who=[Security.Principal.WindowsIdentity]::GetCurrent().User
 foreach($sid in @('S-1-5-18','S-1-5-32-544',$who.Value)){
  $id=New-Object Security.Principal.SecurityIdentifier -ArgumentList $sid
  $flags=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
  $rule=New-Object Security.AccessControl.FileSystemAccessRule -ArgumentList @($id,[Security.AccessControl.FileSystemRights]::FullControl,$flags,[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
  $a.AddAccessRule($rule)
 }
 [IO.Directory]::SetAccessControl($folder,$a)
 if(-not ([IO.Directory]::GetAccessControl($folder)).AreAccessRulesProtected){Fail 'PRIVATE_EXPORT_ACL_FAILED'}
 $phase='COMPANIES'
 $sql="SELECT coalesce(nullif(trim(name_short),''),nullif(trim(name_full),''),'') AS TITLE,coalesce(trim(inn),'') AS INN,onec_guid AS ONEC_GUID FROM customers WHERE onec_type='LEGAL' AND buyer=1 AND deletion_mark=0 AND invalid=0 ORDER BY onec_guid;"
 CsvOut $db $sql (Join-Path $folder 'companies.csv')
 $phase='CONTACTS'
 $sql="SELECT coalesce(nullif(trim(person_name),''),nullif(trim(name_full),''),nullif(trim(name_short),''),'') AS NAME,onec_guid AS ONEC_GUID FROM customers WHERE onec_type='PERSON' AND buyer=1 AND deletion_mark=0 AND invalid=0 ORDER BY onec_guid;"
 CsvOut $db $sql (Join-Path $folder 'contacts.csv')
 $phase='VERIFY'
 $count=(Count $db "SELECT count(*) FROM customers WHERE onec_type='LEGAL' AND buyer=1 AND deletion_mark=0 AND invalid=0;")
 if($count -ne '1941'){Fail 'COMPANIES_MISMATCH'}
 $count=(Count $db "SELECT count(*) FROM customers WHERE onec_type='PERSON' AND buyer=1 AND deletion_mark=0 AND invalid=0;")
 if($count -ne '4486'){Fail 'CONTACTS_MISMATCH'}
 'BITRIX_CSV_COMPANIES=1941'
 'BITRIX_CSV_CONTACTS=4486'
 'BITRIX_CSV_REVIEW_HELD=6'
 'OUTPUT_DIRECTORY='+$folder
 'SOURCE_DB_WRITES=NO'
 'NETWORK_CALLS=NO'
 'RESULT=PASS;STAGE=BITRIX_REAL_CUSTOMER_CSV_PREP'
}catch{
 $gate='RUNTIME_ERROR'
 if($_.Exception.Message -match '^CSV_([A-Z0-9_]+)$'){$gate=$Matches[1]}
 'RESULT=FAIL;STAGE=BITRIX_REAL_CUSTOMER_CSV_PREP;GATE='+$gate+';PHASE='+$phase
 'NO_AUTOMATIC_RETRY=YES'
 exit 1
}
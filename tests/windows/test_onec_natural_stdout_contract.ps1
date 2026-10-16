#requires -version 2
# Preserve the observed physical Win2008R2 PS2 no-wrap contract.
# On physical SRV Write-Output long NAT split into 12 strings, whereas
# [Console]::Out.WriteLine emitted exactly one unchanged NAT string.
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..')).Path
$sourceFile=Join-Path $root 'scripts\windows\onec-system-odata-natural.ps1'
$source=[IO.File]::ReadAllText($sourceFile,[Text.Encoding]::UTF8)
$expect='[Console]::Out.WriteLine((''NAT_''+$encoded))'
if (-not $source.Contains($expect)) { throw 'NAT_CONSOLE_WRITER_MISSING' }
if ($source.Contains('Write-Output (''NAT_''+$encoded)')) {
  throw 'REGRESSION_NAT_WRITE_OUTPUT_WRAP'
}
if (($source.Split([string[]]@($expect),[StringSplitOptions]::None)).Length -ne 2) {
  throw 'NAT_CONSOLE_WRITER_NOT_UNIQUE'
}
$errors=$null
$null=[Management.Automation.PSParser]::Tokenize($source,[ref]$errors)
if ($errors -and $errors.Count -gt 0) { throw 'NAT_PS2_PARSE_FAILED' }
# CI host smoke of Console output, not a physical-PS2 behavioral simulation.
$command="[Console]::Out.WriteLine(('NAT_'+('A'*1000)))"
$emitted=@(& (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -NonInteractive -Command $command)
if ($LASTEXITCODE -ne 0 -or $emitted.Count -ne 1 -or
    $emitted[0] -cne ('NAT_'+('A'*1000))) {
  throw 'NAT_CONSOLE_STDOUT_SINGLE_LINE_FAILED'
}
'ONEC_NAT_PS2_CONSOLE_SOURCE_PIN=PASS'
'ONEC_NAT_CONSOLE_SINGLE_LINE_CI=PASS'
'PHYSICAL_SRV_PS2_NO_WRAP_EVIDENCE=20261016'

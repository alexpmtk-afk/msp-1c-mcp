#requires -version 2
# Retired 2026-10-15: user-profile SQLite pilot violates machine-owned service policy.
# No downloads, no files, no execution: intentionally fail closed.
param([string]$ExpectedComputerName='SRV',[string]$ExpectedSchemaSha256)
$ErrorActionPreference='Stop'
throw 'DEPRECATED_USER_PROFILE_INSTALL_FORBIDDEN__MACHINE_OWNED_LOCAL_SERVICE_REQUIRED'

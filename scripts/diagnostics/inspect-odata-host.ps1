# Safe host inventory: Windows PowerShell 2.0; no elevation or 1C access.
# Only reads Windows service status, local registry markers, and TCP listener table.
param(
    [Parameter(Mandatory=$true)]
    [string]$ExpectedComputerName
)
if ($env:COMPUTERNAME -ine $ExpectedComputerName) {
    Write-Output "HOST_CHECK=FAIL_WRONG_HOST"
    exit 2
}
Write-Output "HOST_CHECK=PASS"
Write-Output ("PS_MAJOR=" + $PSVersionTable.PSVersion.Major)

function Get-SafeServiceStatus {
    param([string]$ServiceName)
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        return $service.Status.ToString().ToUpperInvariant()
    } catch {
        return "ABSENT_OR_UNREADABLE"
    }
}
Write-Output ("W3SVC=" + (Get-SafeServiceStatus -ServiceName "W3SVC"))
Write-Output ("WAS=" + (Get-SafeServiceStatus -ServiceName "WAS"))

try {
    $otherWebServices = @(Get-Service -ErrorAction Stop | Where-Object {
        ($_.Name -match '(?i)^(apache|httpd|nginx)') -or
        ($_.DisplayName -match '(?i)(apache|nginx)')
    })
    Write-Output ("OTHER_WEB_SERVICE_COUNT=" + $otherWebServices.Count)
} catch {
    Write-Output "OTHER_WEB_SERVICE_COUNT=UNKNOWN"
}

try {
    if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\InetStp") {
        Write-Output "IIS_INSTALL_MARKER=PRESENT"
    } else {
        Write-Output "IIS_INSTALL_MARKER=ABSENT"
    }
} catch {
    Write-Output "IIS_INSTALL_MARKER=UNKNOWN"
}

try {
    $config = Join-Path $env:windir "System32\inetsrv\config\applicationHost.config"
    if (Test-Path -LiteralPath $config) {
        Write-Output "IIS_CONFIG_FILE=PRESENT"
    } else {
        Write-Output "IIS_CONFIG_FILE=ABSENT_OR_UNREADABLE"
    }
} catch {
    Write-Output "IIS_CONFIG_FILE=UNKNOWN"
}

try {
    $listeners = @([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners())
    foreach ($port in @(80,443)) {
        $found = $false
        foreach ($listener in $listeners) {
            if ($listener.Port -eq $port) { $found = $true; break }
        }
        if ($found) { Write-Output ("TCP_" + $port + "=LISTENING") }
        else { Write-Output ("TCP_" + $port + "=NOT_LISTENING") }
    }
} catch {
    Write-Output "TCP_80=UNKNOWN"
    Write-Output "TCP_443=UNKNOWN"
}
# Host service/listener presence does NOT prove an OData publication.
Write-Output "ODATA_PUBLICATION=UNVERIFIED"
Write-Output "INFOBASE_ACCESSED=NO"
Write-Output "SYSTEM_CHANGED=NO"

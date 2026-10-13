# Read-only OData host inventory (SRV)

Status: **prepared, not executed on the 1C host** (2026-10-13).

The script `scripts/diagnostics/inspect-odata-host.ps1` works with Windows PowerShell 2.0. It requires no administrator privileges. It reads only Windows service status, IIS presence markers and active local TCP listener ports 80/443. No COM activation, infobase connection, HTTP request, server setting, file write or network route change takes place.

## Where and how to run

Run **only inside the already verified Windows remote-desktop session on the 1C host**, from an ordinary PowerShell prompt. Copy the reviewed script to a transient location or invoke its contents directly from that prompt. Provide the actual machine name as `-ExpectedComputerName` to prevent confusing the HOME workstation with the 1C host. Do not run on the production infobase, which this script does not use.

Example syntax using a locally saved copy (placeholder only; replace with verified computer name):
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\inspect-odata-host.ps1 -ExpectedComputerName "REPLACE_WITH_HOSTNAME"
```

Do not fetch and run unreviewed network scripts, request admin rights, or enable execution policy system-wide.

## Interpretation

- `HOST_CHECK=PASS`: command ran on the expected host (name-based guard).
- `W3SVC`, `WAS`: web publishing service presence/status, **not** proof of OData.
- `OTHER_WEB_SERVICE_COUNT`: possible Apache/nginx services; other deployment forms can be missed.
- `TCP_80` and `TCP_443`: whether a local socket is listening on standard web ports. OData could be hosted on a different port, so negative results are not absolute proof of absence.
- `IIS_INSTALL_MARKER` and `IIS_CONFIG_FILE`: Windows/IIS installation indicators.
- `ODATA_PUBLICATION=UNVERIFIED`: expected on every run, because no publication URL or credentials were supplied. Do **not** interpret this as failure.

If no web server is present, **STOP**: publishing 1C requires authorized technical staff for IIS/Apache configuration and a separate least-privilege 1C service identity. Do not attempt administrator operations under the non-admin account.

If a web listener exists, have authorized staff identify the **test infobase** publication alias and privately provide a validated HTTPS path. Only then use the already implemented read-only `msp_onec_mcp.cli probe` to retrieve `$metadata`. Never use a production infobase alias or disclose credentials in ChatGPT, GitHub or public logs.

Official 1C instructions: https://kb.1ci.com/1C_Enterprise_Platform/FAQ/Development/Integration/Publishing_standard_REST_API_for_your_infobase/?language=en

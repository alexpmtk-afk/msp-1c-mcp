# OneC NewBase forensic V2: recover stage hidden by V1 report

Status: offline Windows PS2 parse and safety CI PASS. Not yet executed on SRV.

## Cause established from first attempt

The first V1 attempt produced `RESULT=FAIL;STAGE=ONE_SHOT_METADATA_READ;GATE=ONE_SHOT_REPORT_FAILED`
and `ONESHOT_TASK_CLEANUP=PASS`. The on-disk report contained only:

    ONEC_NATURAL_STOCK_ONESHOT_RESULT
    RESULT=FAIL

Source inspection shows why no stage is visible: the existing
`onec-natural-stock-schema-preflight.ps1` already prints a sanitized
`RESULT=FAIL;STAGE=<PRECHECK|SCHEMA_GET|EXACT_ARTICLE_FILTER>;DETAILS=REDACTED`,
but the V1 `onec-natural-stock-schema-runner.ps1` discards this line.
The V1 installer then rejects its generic error report. The cause *inside*
the helper is still UNKNOWN. No report supports attributing this to IIS,
authentication, OData or the target article yet.

## V2 retry design

- Existing operational `MspOnecHttpsAgentSystem` unchanged.
- Existing V1 installed metadata helper unchanged and verified against
  exact blob `c82e433205ee3a8353165381c33a7a2f43892b50`.
- Existing V1 diagnostic runner, report and staged files untouched.
- New V2 runner `onec-natural-stock-forensic-v2-runner.ps1` obtained
  from fixed commit `9ee6e13c07f6f5790cdacc063ea4567c13c0a1cf`
  and verified against blob `8299113a6cb5980af9f0b24ba5bf3bc82b5866e3`.
- New manual-only zero-trigger LocalService task:
  `MspOnecNaturalSchemaForensicV2`.
- New report `C:\ProgramData\MspOnecAgent\state\natural-stock-schema-report-v2.txt`.
- Only allowlisted statuses/phase values are written, never a raw exception,
  GUID, customer/product payload, metadata XML or password.
- The V2 task is automatically deleted after a report was written.
  New V2 runner and staged directory are retained for inspection.
- V2 installer refuses to run in a non-admin session, outside SRV, with
  missing/mutated V1 helper, unexpected system task or existing V2 files.

## Authorized one-shot command

Must be executed only by an already authorized administrator of SRV in
PowerShell 2. This never upgrades `SRV\parshin` permissions.

Immutable source commit containing V2 installer:
`6c5956f6eb3c45e72c4215707ff7433345a60b51`

```powershell
$p='C:\ProgramData\MspOnecAgent\bin';$f=Join-Path $env:TEMP 'onec-natural-stock-forensic-v2-once.ps1';& "$p\curl.exe" -q --fail --silent --show-error --noproxy '*' --tlsv1.2 --tls-max 1.2 --proto '=https' --max-redirs 0 --cacert "$p\curl-ca-bundle.crt" --output $f 'https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/6c5956f6eb3c45e72c4215707ff7433345a60b51/scripts/windows/onec-natural-stock-forensic-v2-once.ps1';if($LASTEXITCODE -ne 0){throw 'V2_INSTALLER_DOWNLOAD_FAILED'};& "$PSHOME\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $f -ExpectedComputerName 'SRV'
```

The *outer* status `RESULT=PASS;STAGE=DIAGNOSTIC_CAPTURE_ONLY` means only
that a safely filtered result was captured, **not** that the OData request
or article query succeeded. The meaningful fields are:

- `PROBE_PHASE=PRECHECK`: local identity, encrypted credential or setup problem.
- `PROBE_PHASE=SCHEMA_GET`: metadata HTTP, size, XML parsing or schema discovery.
- `PROBE_PHASE=EXACT_ARTICLE_FILTER`: exact code/article filtered GET or response parsing.
- `PROBE_PHASE=COMPLETE` with `PROBE_RESULT=PASS`: probe completed; inspect
  the reported match counts independently.
- `PROBE_PHASE=NO_CLASSIFIED_STAGE` / `RUNNER_FAILURE`: diagnose runner layer.

Do NOT blindly retry after errors: V2 refuses existing report/staged files.
Review the status before deciding on an authorized and scoped cleanup.
Do NOT change production 1C, current relay commands, Hermes registration
or any existing scheduled task.

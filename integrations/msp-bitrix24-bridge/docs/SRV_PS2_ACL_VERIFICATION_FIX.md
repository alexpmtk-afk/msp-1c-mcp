# Windows PowerShell 2.0 ACL verification fix — 2026-10-15

SRV observed:
- Task MspBitrix24Bridge correctly registered under LOCAL SERVICE.
- The first ACL grant executed on **two explicit files** with icacls exit codes 0.
- The recovery helper returned `LOCAL_REPAIR_EXCEPTION` in `VERIFY_FILES`.

**Cause:** `Get-Acl -LiteralPath` is only available beginning with Windows PowerShell 3.0 (Microsoft PowerShell Get-Acl documentation). Native SRV is PowerShell 2.0. Hashing or ACE verification might already have succeeded; script did not distinguish them.

Changes: replace `Get-Acl -LiteralPath $f` with compatible `Get-Acl -Path $f` for fixed controlled absolute files. Tests prohibit the incompatible parameter.

**Do not rerun the changing repair script.** First run a read-only verification of both hashes and SID-based explicit ALLOW ACLs using `Get-Acl -Path` on SRV. Confirm both automatic task triggers remain OFF. Only after read-only PASS repeat known pinned smoke-system.ps1 and confirm a fresh SAFE_IDLE heartbeat. No Bitrix24 network or 1C writes are enabled.

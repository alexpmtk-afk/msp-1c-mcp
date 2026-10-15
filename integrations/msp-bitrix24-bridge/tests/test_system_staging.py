"""Offline gate checks: staged LocalService task must be disconnected and not auto-run."""
from pathlib import Path
import unittest
root=Path(__file__).resolve().parents[1]
def src(n): return (root/"bin"/n).read_text(encoding="utf-8-sig")
class StagingTest(unittest.TestCase):
    def test_install_is_manual_first(self):
        s=src("install-system.ps1")
        for token in ("LOCAL SERVICE","Triggers.Create(8)","Triggers.Create(2)",
                      "$boot.Enabled=$false","$daily.Enabled=$false",
                      "RUN_AS_LOCAL_SERVICE=YES","CUSTOMERS_SYNC=OFF","ONEC_WRITES=OFF"):
            self.assertIn(token,s)
        self.assertNotIn("MspOnecHttpsAgentSystem",s)
    def test_partial_stage_resume_is_deprecated(self):
        s=src("resume-system.ps1")
        self.assertIn("DEPRECATED_REQUIRES_ACL_REVIEW", s)
        self.assertNotIn("RegisterTaskDefinition", s)
        self.assertNotIn("/inheritance:r", s)

    def test_install_acl_before_children_and_no_recursive_acl(self):
        s=src("install-system.ps1")
        self.assertLess(s.index("$phase='APPLY_ROOT_ACL'"),s.index("$phase='STAGE_LOCAL_FILES'"))
        self.assertIn("VERIFY_STAGED_ACCESS",s)
        self.assertNotIn("'/T' | Out-Null",s)

    def test_new_installs_resolve_icacls_absolutely(self):
        s=src("install-system.ps1")
        self.assertIn("System32\icacls.exe", s)
        self.assertIn("Sysnative\icacls.exe", s)
        self.assertIn("ICACLS_MISSING", s)
        self.assertNotIn("& icacls.exe", s)
    def test_readonly_runtime_diagnostic(self):
        s=src("diagnose-runtime.ps1")
        for token in ("TASK_LAST_RESULT", "TASK_ACTIONS", "ACTION_FILE_ARGUMENT_EXPECTED",
                      "TASK_IDENTITY_LOCAL_SERVICE", "SCRIPT_HASH_VALID",
                      "POLICY_HASH_VALID", "TASK_EVENT=", "NO_CHANGES=YES"):
            self.assertIn(token, s)
        for forbidden in ("RegisterTaskDefinition", "Invoke-WebRequest", "Run($null)",
                          "DeleteTask(", "Remove-Item", "Get-Content -Path", "MspOnecHttpsAgentSystem"):
            self.assertNotIn(forbidden, s)
    def test_acl_recovery_is_two_files_only(self):
        s=src("repair-file-acl.ps1")
        for token in ("ConfirmRepair","S-1-5-19","S-1-5-18","S-1-5-32-544",
                      "AUTOSTART_MUST_BE_OFF", "TASK_COMMAND_MISMATCH",
                      "BRIDGE_HASH_MISMATCH", "POLICY_HASH_MISMATCH",
                      "FILES_REPAIRED=2", "LOCAL_SERVICE_ACCESS=RESTORED"):
            self.assertIn(token,s)
        for forbidden in ("'/T'","/inheritance:r","DeleteTask(", "RegisterTaskDefinition",
                          "Takeown", "Set-Acl", "Invoke-WebRequest", "MspOnecHttpsAgentSystem"):
            self.assertNotIn(forbidden,s)
        self.assertIn("foreach($f in @($bridge,$policy))",s)
    def test_ps2_acl_verification_avoids_ps3_literalpath(self):
        # Microsoft documents Get-Acl -LiteralPath as introduced in PS 3.0.
        for name in ("repair-file-acl.ps1", "diagnose-runtime.ps1"):
            s=src(name)
            self.assertNotIn("Get-Acl -LiteralPath", s)
            self.assertIn("Get-Acl -Path", s)

    def test_native_system_smoke(self):
        s=src("smoke-system.ps1")
        for token in ("S-1-5-19","Run($null)","SAFE_IDLE","FRESH_SYSTEM_HEARTBEAT_MISSING"):
            self.assertIn(token,s)
        self.assertNotIn("RegisterTaskDefinition",s)
    def test_enable_separate_gates(self):
        s=src("enable-system.ps1")
        for token in ("ConfirmEnable","NO_VALID_SMOKE","STALE_SMOKE",
                      "UNSAFE_POLICY","Triggers.Item(1).Enabled=$true",
                      "Triggers.Item(2).Enabled=$true"):
            self.assertIn(token,s)
    def test_enable_uses_localized_verified_account_and_pinned_safe_files(self):
        s=src("enable-system.ps1")
        self.assertIn("$account=$d.Principal.UserId", s)
        self.assertIn("RegisterTaskDefinition('MspBitrix24Bridge',$d,6,$account,$null,5,$null)",s)
        self.assertNotIn("RegisterTaskDefinition('MspBitrix24Bridge',$d,6,'NT AUTHORITY",s)
        for marker in ("ALREADY_ENABLED_OR_INCONSISTENT","TASK_DISABLED",
                       "BRIDGE_HASH_CHANGED","POLICY_HASH_CHANGED",
                       "POST_ENABLE_IDENTITY_MISMATCH","WRONG_ENTRYPOINT"):
            self.assertIn(marker,s)
    def test_no_bitrix_network_config(self):
        s=src("bridge.ps1")
        self.assertNotIn("Invoke-WebRequest",s)
        self.assertNotIn("HttpWebRequest",s)
        p=(root/"config/bridge.ini").read_text(encoding="ascii")
        for x in ("ACTIVE=0","CUSTOMERS_READ=0","PRODUCTS_READ=0","INVOICES_WRITE=0"):
            self.assertIn(x,p)
if __name__=="__main__":unittest.main()

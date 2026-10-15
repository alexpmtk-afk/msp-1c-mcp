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
    def test_no_bitrix_network_config(self):
        s=src("bridge.ps1")
        self.assertNotIn("Invoke-WebRequest",s)
        self.assertNotIn("HttpWebRequest",s)
        p=(root/"config/bridge.ini").read_text(encoding="ascii")
        for x in ("ACTIVE=0","CUSTOMERS_READ=0","PRODUCTS_READ=0","INVOICES_WRITE=0"):
            self.assertIn(x,p)
if __name__=="__main__":unittest.main()

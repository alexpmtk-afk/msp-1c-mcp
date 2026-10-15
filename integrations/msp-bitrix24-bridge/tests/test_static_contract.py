"""Offline fail-closed checks for the Bitrix24 bootstrap. No network access."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "bin"

def read(name):
    return (BIN / name).read_text(encoding="utf-8-sig")

class BootstrapSafety(unittest.TestCase):
    def test_default_policy_never_enables_data(self):
        d = (ROOT / "config" / "bridge.ini").read_text(encoding="ascii")
        for key in ("ACTIVE", "CUSTOMERS_READ", "PRODUCTS_READ", "INVOICES_WRITE"):
            self.assertIn(key + "=0", d)
            self.assertNotIn(key + "=1", d)

    def test_agent_is_machine_only_and_idle(self):
        s = read("bridge.ps1")
        for marker in ("S-1-5-19", "POLICY_INVALID", "POLICY_DUPLICATE",
                       "CAPABILITY_NOT_IMPLEMENTED", "SAFE_IDLE",
                       "CUSTOMERS_SYNC=OFF", "WRITES=OFF"):
            self.assertIn(marker, s)
        for forbidden in ("Invoke-Expression", "Invoke-WebRequest",
                          "HttpWebRequest", "Start-Process", "github.com",
                          "tail76ae70", "crm.company.add"):
            self.assertNotIn(forbidden, s)

    def test_local_service_task_and_boot(self):
        s = read("install-system.ps1")
        for marker in ("S-1-5-19", "LOCAL SERVICE", "Triggers.Create(8)",
                       "Triggers.Create(2)", "PT5M", "P1D", "ALREADY_STAGED",
                       "C:\\ProgramData"):
            if marker == "C:\\ProgramData":
                # the root is derived from the machine-wide special folder
                self.assertIn("CommonApplicationData", s)
            else:
                self.assertIn(marker, s)
        self.assertNotIn("MspOnecHttpsAgentSystem", s)
        self.assertNotIn("RegisterTaskDefinition('MspOnec", s)

    def test_inventory_is_only_read_only_metadata(self):
        s = read("inspect-customers-metadata.ps1")
        for marker in ("127.0.0.1:8085/NewBase", "'GET'",
                       "$metadata", "CUSTOMER_RECORDS_EXPORTED=NO",
                       "DATA_WRITES=NO"):
            self.assertIn(marker, s)
        for forbidden in ("crm.company.add", "crm.contact.add",
                          "CreateFile(", ".Method='POST'", "github.com"):
            self.assertNotIn(forbidden, s)

    def test_rollback_only_disables_own_task(self):
        s = read("rollback-system.ps1")
        self.assertIn("MspBitrix24Bridge", s)
        self.assertIn("$t.Enabled=$false", s)
        self.assertNotIn("DeleteTask", s)
        self.assertNotIn("Remove-Item", s)

if __name__ == "__main__":
    unittest.main()

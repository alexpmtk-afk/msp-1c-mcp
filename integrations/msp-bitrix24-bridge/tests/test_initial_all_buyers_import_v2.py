"""V2 one-time buyer import: first-batch SQLite bug regression."""
import hashlib
import unittest
from pathlib import Path

BIN=Path(__file__).resolve().parents[1]/"bin"
class ImportV2(unittest.TestCase):
    def test_first_batch_safe_argument_and_private_failure_codes(self):
        p=BIN/"import-all-newbase-buyers-once-v2.ps1"
        s=p.read_text(encoding="ascii")
        self.assertIn("$pending=SqlRead $query",s)
        self.assertNotIn('$pending=SqlRead "SELECT ',s)
        self.assertIn("$psi.RedirectStandardInput=$true",s)
        self.assertIn("$psi.RedirectStandardError=$true",s)
        self.assertIn("$psi.Arguments='-readonly -batch -bail",s)
        self.assertIn("$phase='READ_SOURCE_SQL'",s)
        self.assertIn("$phase='READ_SOURCE_PARSE'",s)
        self.assertIn("EXCEPTION_TYPE=",s)
        self.assertIn("ERROR_LINE=",s)
        self.assertIn("NO_BLIND_RETRY=YES",s)
        self.assertNotIn("DeleteTask(",s)
        self.assertNotIn("RegisterTaskDefinition(",s)
        self.assertNotIn("D:\\DATA\\WorkBase",s)
        self.assertNotIn("\r",s)
        print("V2_BULK_WORKER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
    def test_source_scope_remains_all_6433(self):
        s=(BIN/"import-all-newbase-buyers-once-v2.ps1").read_text("ascii")
        for marker in ("6433:1941:4486:6","MspOneTimeAllBuyersImportV2",
                       "CRM_DETAILS_BACKREAD_MISMATCH",
                       "crm.item.add?entityTypeId=",
                       "msp_initial_inflight",
                       "NEWBASE_ALL_BUYERS_INITIAL_CRM_IMPORT_V2",
                       "bitrix-initial-all-buyers-v2.status"):
            self.assertIn(marker,s)

if __name__=="__main__":
    unittest.main()

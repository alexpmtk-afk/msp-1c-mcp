"""V4 fail-closed recovery after previously mapped 45 buyers."""
from pathlib import Path
import hashlib
import unittest
BIN=Path(__file__).resolve().parents[1]/"bin"
class LauncherV4(unittest.TestCase):
    def test_exact_old_failure_and_no_duplicate_create(self):
        p=BIN/"start-initial-all-buyers-v4.ps1";s=p.read_text("ascii")
        for x in (
            "MspNewBaseInitialImportV3", "MspNewBaseInitialImportV4",
            "V3_FAILURE_RECEIPT_CHANGED",
            "STATUS=FAIL;GATE=CRM_VISIBLE_NAME_MISMATCH;PHASE=VERIFY_EXISTING",
            "ERROR_ID=NEWBASE_CRM_VISIBLE_NAME_MISMATCH",
            "MAPPED=45;TARGET=6433",
            "LOCAL_45_ZERO_INFLIGHT_CHANGED", "'45:0'",
            "INITIAL_V4_SAFE_RESUME_GATE=PASS",
            "bitrix-initial-all-buyers-v4.status",
            "import-all-newbase-buyers-once-v4.ps1",
            "48b4a0a4f81a63a317fdf0cb9e88903a8c5f7e72",
            "541bf0d17e3a2de1add5fcd5046323a5b50e0f56a856679200b791d60428ec85",
            "NO_AUTOMATIC_RETRY=YES", "NEW_TASK_TRIGGERS=0",
            "SOURCE_SNAPSHOT_NOT_6433","MspCustomerStoreSync",
        ):self.assertIn(x,s)
        for x in ("Triggers.Create", "DeleteTask(", "Stop-Process",
                  "crm.item.add?", "crm.item.update?", "D:\\DATA\\WorkBase"):
            self.assertNotIn(x,s)
        self.assertNotIn("\r",s)
        print("BULK_V4_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

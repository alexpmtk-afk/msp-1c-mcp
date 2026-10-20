"""V3 initial buyer one-shot launcher safety: old V2 must remain intact."""
import hashlib
from pathlib import Path
import unittest
BIN=Path(__file__).resolve().parents[1]/"bin"
class InitialV3Launcher(unittest.TestCase):
    def test_v3_only_after_known_exact_v2_and_audit(self):
        f=BIN/"start-initial-all-buyers-v3.ps1"
        s=f.read_text("ascii")
        for marker in (
            "#requires -version 2",
            "MspNewBaseInitialImportV3",
            "MspNewBaseInitialImportV2",
            "V2_FAILURE_RECEIPT_CHANGED",
            "STATUS=FAIL;GATE=CRM_DETAILS_BACKREAD_MISMATCH",
            "PHASE=CRM_CREATE_BACKREAD",
            "MAPPED=5;TARGET=6433",
            "READONLY_AUDIT_CHANGED",
            "TOTAL_INFLIGHT=15;IDENTITY_VERIFIED=15",
            "COMMENTS_EXACT=13",
            "COMMENTS_DIFFERENT=2",
            "LOCAL_5_15_STATE_CHANGED",
            "'5:15'",
            "INITIAL_V3_SAFE_RESUME_GATE=PASS",
            "MspCustomerStoreSync",
            "NEW_TASK_TRIGGERS=0",
            "Triggers.Count -ne 0",
            "SOURCE_SNAPSHOT_NOT_6433",
            "bitrix-initial-all-buyers-v3.status",
            "import-all-newbase-buyers-once-v3.ps1",
            "66e46238fef9f0d27bfafc9e1e090de135bfd565",
            "dea6827233bc2b948f405b8a760568cd68cca11bb6c25559a4edc1aea5f75d45",
            "-MaxBatches 800 -BatchSize 10",
            "NO_AUTOMATIC_RETRY=YES",
        ):
            self.assertIn(marker,s)
        for forbidden in (
            "Triggers.Create", "DeleteTask(", "crm.item.add?",
            "Remove-Item", "Stop-Process", "D:\\DATA\\WorkBase"
        ):
            self.assertNotIn(forbidden,s)
        self.assertNotIn("\r",s)
        print("BULK_V3_LAUNCHER_SHA256="+hashlib.sha256(f.read_bytes()).hexdigest())

if __name__=="__main__":unittest.main()

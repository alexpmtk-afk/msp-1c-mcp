"""One-time V5 recovery from exactly 5245+0, never repeat ambiguous creates."""
from pathlib import Path
import hashlib
import unittest
B=Path(__file__).resolve().parents[1]/"bin"
class V5Launcher(unittest.TestCase):
 def test_state_guard_and_no_schedule(self):
  p=B/"start-initial-all-buyers-v5.ps1";s=p.read_text("ascii")
  for x in ("V4_FAILURE_RECEIPT_CHANGED", "STATUS=FAIL;GATE=CURL_FAILED",
            "ERROR_ID=NEWBASE_CURL_FAILED", "MAPPED=5245;TARGET=6433",
            "MspNewBaseInitialImportV4", "MspNewBaseInitialImportV5",
            "'5245:0:1188'", "MAPPED_CRM_ID_DUPLICATES",
            "INITIAL_V5_SAFE_RESUME_GATE=PASS","bitrix-initial-6433-v5",
            "bitrix-initial-all-buyers-v5.status",
            "import-all-newbase-buyers-once-v5.ps1",
            "565dd5967d27bf80a65be6bbc44cfb2d6adf9717",
            "d50788a0dad2fca5ec42363d4312a0281cb05a782bb2308a4676d60c52959e67",
            "NEW_TASK_TRIGGERS=0","NO_AUTOMATIC_RETRY=YES",
            "MspCustomerStoreSync","SOURCE_SNAPSHOT_NOT_6433"):
   self.assertIn(x,s)
  for x in ("Triggers.Create", "DeleteTask(", "Stop-Process", "crm.item.add?",
            "Remove-Item", "D:\\DATA\\WorkBase"):
   self.assertNotIn(x,s)
  self.assertNotIn("\r",s)
  print("BULK_V5_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

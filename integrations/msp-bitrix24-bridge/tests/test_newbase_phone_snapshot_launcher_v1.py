"""One-time SRV LOCAL_SERVICE launch guard for isolated SQLite TEST phone snapshot."""
import hashlib
from pathlib import Path
import unittest

BASE=Path(__file__).resolve().parents[1]/"bin"
RUNNER=BASE/"start-newbase-phone-snapshot-local-v1.ps1"

class SnapshotLauncher(unittest.TestCase):
 def test_launcher_safety(self):
  script=RUNNER.read_text(encoding="ascii")
  for required in (
   "#requires -version 2", "SRV", "PS2_X64_REQUIRED", "ADMIN_REQUIRED",
   "V2", "COVERAGE_NOT_ACCEPTED", "PHONE_NUMBER_ROWS=4068",
   "BUYERS_WITH_PHONE=4067", "PRIOR_TASK_NOT_PASS", "TASK_ALREADY_EXISTS",
   "SNAPSHOT_ALREADY_EXISTS", "MspNewbasePhoneSnapshotLocalV1",
   "S-1-5-19", "ExecutionTimeLimit='PT60M'", "TRIGGERS_PRESENT",
   "49d1598e56c11d4b7ee061b227ebf0b3dbe5f76a09f2ca7191d9204eeae837ec",
   "fbfbdaa3b07e3e16cec1a3e3aacf860471fc44ba",
   "CRM_WRITES=0", "ONEC_WRITES=0", "CUSTOMERS_DB_WRITES=0",
   "PHONE_STAGE_STATUS_FILE=", "PHONE_STAGE_TASK=STARTED",
   "RESULT=STARTED;STAGE=PHONE_STAGE_SRV_LOCAL_V1"
  ):
   self.assertIn(required,script)
  for forbidden in (
   "Triggers.Create", "DeleteTask(", "Remove-Item", "crm.item.update",
   "crm.requisite.update", "Send-MailMessage", "Set-ExecutionPolicy",
   "D:\\DATA\\NewBase", "D:\\DATA\\WorkBase", "Get-Content $worker"
  ):
   self.assertNotIn(forbidden,script)
  self.assertNotIn("\r",script)
  print("PHONE_STAGE_LAUNCHER_SHA256="+hashlib.sha256(RUNNER.read_bytes()).hexdigest())

if __name__=="__main__":unittest.main()

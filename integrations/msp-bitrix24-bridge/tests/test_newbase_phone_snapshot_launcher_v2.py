"""One-time SRV LOCAL_SERVICE launch guard for isolated SQLite TEST phone snapshot."""
import hashlib
from pathlib import Path
import unittest

BASE=Path(__file__).resolve().parents[1]/"bin"
RUNNER=BASE/"start-newbase-phone-snapshot-local-v2.ps1"

class SnapshotLauncherV2(unittest.TestCase):
 def test_launcher_safety(self):
  script=RUNNER.read_text(encoding="ascii")
  for required in (
   "#requires -version 2", "SRV", "PS2_X64_REQUIRED", "ADMIN_REQUIRED",
   "V2", "COVERAGE_NOT_ACCEPTED", "PHONE_NUMBER_ROWS=4068",
   "BUYERS_WITH_PHONE=4067", "PRIOR_TASK_NOT_PASS", "TASK_ALREADY_EXISTS",
   "SNAPSHOT_ALREADY_EXISTS", "MspNewbasePhoneSnapshotLocalV2",
   "S-1-5-19", "ExecutionTimeLimit='PT60M'", "TRIGGERS_PRESENT",
   "68193c03f2c7f0dff11e11908b8443fdc7cfc6b1b35839b5291fec9d891453dc",
   "ccc47387a108225c15f5c3c8940c9d5fddc88523",
   "CRM_WRITES=0", "ONEC_WRITES=0", "CUSTOMERS_DB_WRITES=0",
   "PHONE_STAGE_STATUS_FILE=", "PHONE_STAGE_TASK=STARTED",
   "RESULT=STARTED;STAGE=PHONE_STAGE_SRV_LOCAL_V2"
  ):
   self.assertIn(required,script)
  for forbidden in (
   "Triggers.Create", "DeleteTask(", "Remove-Item", "crm.item.update",
   "crm.requisite.update", "Send-MailMessage", "Set-ExecutionPolicy",
   "D:\\DATA\\NewBase", "D:\\DATA\\WorkBase", "Get-Content $worker"
  ):
   self.assertNotIn(forbidden,script)
  for preflight in ("PHONE_SNAPSHOT_V2_RETRY_GATE=PASS","V1_FAILURE_RECEIPT_CHANGED", "V1_TASK_NOT_FAILED_IDLE","customer-phone-snapshot-v1.status","customer-phone-snapshot-v2.status","GATE=NETWORK;PII_EXPORTED=0","MspNewbasePhoneSnapshotLocalV1","snapshot-newbase-phone-source-local-v2.ps1"):
   self.assertIn(preflight,script)
  self.assertNotIn("\r",script)
  print("PHONE_STAGE_V2_LAUNCHER_SHA256="+hashlib.sha256(RUNNER.read_bytes()).hexdigest())

if __name__=="__main__":unittest.main()

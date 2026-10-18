"""One-shot SRV LOCAL SERVICE launcher for complete read-only mapped CRM phone audit."""
from pathlib import Path
import hashlib,unittest
P=Path(__file__).resolve().parents[1]/"bin"/"start-bitrix-phone-presence-full-readonly-v1.ps1"
class FullPhonePresenceLauncher(unittest.TestCase):
 def test_launcher_guard(self):
  s=P.read_text("ascii")
  for x in ("#requires -version 2","PS2_X64_REQUIRED","ADMIN_REQUIRED",
    "MspBitrixPhoneFieldsReadOnlyPilotV1","MspNewbasePhoneSnapshotLocalV2",
    "PILOT_TASK_NOT_IDLE_PASS","SNAPSHOT_TASK_NOT_IDLE_PASS",
    "PHONE_SOURCE_NOT_ACCEPTED","INITIAL_SOURCE_CHANGED","AUTO_UPDATE=OFF",
    "bitrix-phone-existing-fields-probe-v1.status","customer-phone-snapshot-v2.status",
    "bitrix-phone-presence-audit-v1.status","MspBitrixPhonePresenceFullReadOnlyV1",
    "S-1-5-19","ExecutionTimeLimit='PT4H'",
    "82774daa55266e468cd2cd592806cbfa2fbcb15b",
    "9ee34849b7062e8d0b319b76f62c74a3231281e75aafb86c83f0058bc711546d",
    "WORKER_PS2_PARSE_FAILED","TRIGGERS_PRESENT",
    "FULL_AUDIT_TASK=STARTED","CRM_MODE=READ_ONLY","CRM_WRITES=0",
    "ONEC_WRITES=0","CUSTOMERS_DB_WRITES=0","PHONE_DB_WRITES=0"):
   self.assertIn(x,s)
  for forbidden in ("Triggers.Create","DeleteTask(", "Remove-Item",
    "crm.item.update", "crm.item.add", "crm.requisite.update",
    "Enable-ScheduledTask", "Set-ExecutionPolicy"):
   self.assertNotIn(forbidden,s)
  self.assertNotIn("\r",s)
  print("FULL_BITRIX_PHONE_READONLY_LAUNCHER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

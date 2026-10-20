"""Read-only LOCAL SERVICE Bitrix fm probe launch guard and SHA pin."""
from pathlib import Path
import unittest,hashlib
ROOT=Path(__file__).resolve().parents[1]/"bin"
P=ROOT/"start-bitrix-existing-phones-readonly-pilot-v1.ps1"
class BitrixPhonePilotLauncher(unittest.TestCase):
 def test_guarded_launcher(self):
  s=P.read_text("ascii")
  for need in (
   "#requires -version 2","PS2_X64_REQUIRED","ADMIN_REQUIRED",
   "MspNewbasePhoneSnapshotLocalV2","MspBitrixPhoneFieldsReadOnlyPilotV1",
   "SNAPSHOT_TASK_NOT_IDLE_PASS","SNAPSHOT_PASS_NOT_CONFIRMED",
   "PILOT_TASK_ALREADY_EXISTS","PILOT_ALREADY_EXECUTED",
   "phone-source-newbase-v1.sqlite", "customer-phone-snapshot-v2.status",
   "S-1-5-19","ExecutionTimeLimit='PT20M'",
   "probe-bitrix-existing-phones-readonly-v1.ps1","d358c0cfc63da080730cb7b4c597069e0c42f3b805e9ad792f4eec72f9bdec77",
   "a295d05e9d1a5697f3bcebe5e5cd3d58f405d38e",
   "WORKER_PS2_PARSE_FAILED", "UNEXPECTED_TRIGGERS",
   "CRM_WRITES=0", "ONEC_WRITES=0", "CUSTOMERS_DB_WRITES=0",
   "PHONE_DB_WRITES=0", "AUTO_UPDATE=OFF", "READONLY_PILOT_V1"):
   self.assertIn(need,s)
  for ban in ("Triggers.Create","DeleteTask(","Remove-Item","crm.item.update",
   "crm.requisite.update","crm.item.add","New-ItemProperty","Set-ExecutionPolicy"):
   self.assertNotIn(ban,s)
  self.assertNotIn("\r",s)
  print("BITRIX_PHONE_READONLY_LAUNCHER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

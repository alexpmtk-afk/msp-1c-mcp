"""Only explicitly launched single-card CRM name update; no recurring task."""
from pathlib import Path
import unittest,hashlib
P=Path(__file__).resolve().parents[1]/"bin"/"start-bitrix-unnamed-name-fix-pilot-v1.ps1"
class FixPilotLaunch(unittest.TestCase):
 def test_contract(self):
  s=P.read_text("ascii")
  for item in ("#requires -version 2","ADMIN_REQUIRED","PS2_X64_ONLY","MspBitrixUnnamedNamesAuditV1",
    "MspBitrixNameFixPilotV1","S-1-5-19","TASK_ALREADY_EXISTS","PILOT_ALREADY_ATTEMPTED",
    "2c643d6657f66c1b37b4c63455ac731eab78c1eaccfc843534710dea4297f9e6",
    "8692dfd5042da65e476411b0094b361bff0412fa",
    "WORKER_HASH_MISMATCH","WORKER_PS2_PARSE_INVALID","AUDIT_NOT_ACCEPTED",
    "AUDIT_TASK_NOT_PASS","CONCURRENT_TASK","NAME_FIX_WORKER_VERIFIED=PASS",
    "CRM_WRITES_MAX=1","ONEC_WRITES=0","AUTO_UPDATE=OFF","TRIGGERS_PRESENT"):
   self.assertIn(item,s)
  for bad in ("Triggers.Create","-Mode Batch","crm.item.add","crm.item.delete","Remove-Item","Set-ScheduledTask"):
   self.assertNotIn(bad,s)
  self.assertNotIn("\r",s)
  print("BITRIX_UNNAMED_FIX_PILOT_LAUNCHER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

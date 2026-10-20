"""One-shot SRV PS2 launch contract for live read-only Bitrix placeholder/duplicate audit."""
from pathlib import Path
import hashlib,unittest
P=Path(__file__).resolve().parents[1]/"bin"/"start-bitrix-unnamed-names-audit-v1.ps1"
class UnnamedReadOnlyLauncher(unittest.TestCase):
 def test_launch_contract(self):
  s=P.read_text("ascii")
  for item in ("#requires -version 2","LOCAL SERVICE","ADMIN_REQUIRED","PS2_X64_ONLY",
    "MspBitrixUnnamedNamesAuditV1","S-1-5-19","REPORT_ALREADY_EXISTS",
    "eec9fb238804e0269ab18f6cc36a08beea634882",
    "e1e8d4bddf2e3729c6bbe14536d4898877f733027ff119148b3b5905796899f2",
    "WORKER_HASH_MISMATCH","NAME_AUDIT_WORKER_VERIFIED=PASS",
    "6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852",
    "TRIGGERS_PRESENT","CONCURRENT_TASK_RUNNING","CRM_WRITES=0",
    "ONEC_WRITES=0","AUTO_UPDATE=OFF"):
   self.assertIn(item,s)
  for forbidden in ("Triggers.Create","crm.item.update", "crm.item.add","DELETE FROM",
    "Remove-Item","Set-ScheduledTask","Invoke-WebRequest"):
   self.assertNotIn(forbidden,s)
  self.assertNotIn("\r",s)
  print("BITRIX_UNNAMED_READONLY_LAUNCHER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

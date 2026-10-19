"""No-trigger hash-pinned Windows PS2 launch of a single 20-contact name correction batch."""
from pathlib import Path
import hashlib,unittest
P=Path(__file__).resolve().parents[1]/"bin"/"start-bitrix-unnamed-name-batch20-v1.ps1"
class NameBatchLauncher(unittest.TestCase):
 def test_pinned_and_separate_local_service_worker(self):
  s=P.read_text("ascii")
  for v in ("#requires -version 2","ADMIN_REQUIRED","PS2_X64_REQUIRED",
    "MspBitrixNameFixPilotV1","MspBitrixNameFixBatch20V1","S-1-5-19",
    "b997ad9ea4e7d57417862309db08133b2c9bc4f78ee294925d05bf0045b995e4",
    "92e99a141e7e5a7c185636577f05e9fd7e5a5f7b",
    "6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852",
    "WORKER_HASH_MISMATCH","NAME_BATCH20_WORKER_VERIFIED=PASS",
    "PS2_PARSE_FAILED","ALREADY_ATTEMPTED","PILOT_NOT_ACCEPTED",
    "PILOT_TASK_NOT_DONE","TASK_CONCURRENT","TRIGGERS_PRESENT",
    "-MaxCards 20","CRM_WRITES_MAX=20","ONEC_WRITES=0","AUTO_UPDATE=OFF"):
   self.assertIn(v,s)
  for forbidden in ("Triggers.Create","crm.item.add","crm.item.update","crm.item.delete",
     "Remove-Item","Set-ScheduledTask","-Mode Bulk"):
   self.assertNotIn(forbidden,s)
  self.assertNotIn("\r",s)
  print("BITRIX_UNNAMED_BATCH20_LAUNCHER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

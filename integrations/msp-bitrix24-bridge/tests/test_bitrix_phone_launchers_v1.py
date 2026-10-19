"""Verify SRV deployment remains triggerless and all downloaded scripts are SHA pinned."""
from pathlib import Path
import unittest,hashlib
ROOT=Path(__file__).resolve().parents[1]/"bin"
class PhoneLaunchers(unittest.TestCase):
 def test_queue_launcher(self):
  p=ROOT/"start-bitrix-phone-queue-v1.ps1"; s=p.read_text("ascii")
  for v in ("MspCustomerPhoneUnifyV1","MspBitrixPhoneQueueV1","S-1-5-19",
    "4fb8d496db87b3dda68b3d658419a3f0514720d45e4fea1ab7c8c08f561b2236",
    "18e2d95e6c90f6da421a69c60f192f1cf48d090","PS2_PARSE_FAILED",
    "customer-unified-phones-v1.status","CRM_WRITES=0","AUTO_UPDATE=OFF",
    "ALREADY_ATTEMPTED","TRIGGERS_PRESENT"):
   self.assertIn(v,s)
  self.assertNotIn("Triggers.Create",s)
  self.assertNotIn("crm.item.update",s)
  print("BITRIX_PHONE_QUEUE_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
 def test_real_single_company_pilot_launcher(self):
  p=ROOT/"start-bitrix-phone-pilot-v1.ps1";s=p.read_text("ascii")
  for v in ("MspBitrixPhonePilotV1","MspBitrixPhoneQueueV1",
    "cbc07e9fc2f7ab3be63a6ae637fb1bfbad5f8efeb028e0ad9b500e66bc408a8c",
    "8f9e8e355410f6e8d9ee70ba254f489d577b9182",
    "6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852",
    "-Mode Pilot -MaxCards 1","PILOT_ALREADY_ATTEMPTED","PILOT_STATUS_FILE",
    "QUEUE_NOT_ACCEPTED","QUEUE_TASK_NOT_PASS","TASK_CONCURRENT",
    "CRM_WRITES_MAX=1","TRIGGERS_PRESENT","AUTO_UPDATE=OFF"):
   self.assertIn(v,s)
  self.assertNotIn("Triggers.Create",s)
  self.assertNotIn("-Mode Batch",s)
  print("BITRIX_PHONE_PILOT_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

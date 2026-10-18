"""V2 schema metadata read-only safe continuation after V1 parse failure."""
import hashlib
import unittest
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class LauncherV2(unittest.TestCase):
 def test_failure_gate_and_readonly_task(self):
  p=B/"start-newbase-contactinfo-metadata-readonly-v2.ps1";s=p.read_text("ascii")
  for x in ("MspNewbasePhoneMetadataProbeV1",
    "MspNewbasePhoneMetadataProbeV2",
    "STATUS=FAIL;PHASE=PARSE_CONTACTINFO_METADATA;GATE=RUNTIME_ERROR",
    "V1_FAILURE_RECEIPT_CHANGED","V1_TASK_NOT_IDLE",
    "PHONE_V2_SAFE_RETRY_GATE=PASS",
    "customer-phone-contactinfo-metadata-v2.txt",
    "probe-newbase-contactinfo-metadata-readonly-v2.ps1",
    "ab293a70458569ceef67f7a7149e61d2cb6befb8",
    "e416f9039fde375b5b39c87d87753233ea38805366eb5e25c4c6710e105fa385",
    "6433:6433:0","AUTO_UPDATE=OFF",
    "PHONE_METADATA_READONLY_V2_ACCEPTED",
    "PHONE_METADATA_READONLY_V2_AWAITING_RECEIPT"):
   self.assertIn(x,s)
  for x in ("DeleteTask(","Triggers.Create","Remove-Item","crm.item.add?",
            "crm.item.update?","D:\\DATA\\WorkBase"):
   self.assertNotIn(x,s)
  self.assertNotIn("\r",s)
  print("PHONE_METADATA_V2_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

"""V2 schema metadata read-only safe continuation after V1 parse failure."""
import hashlib
import unittest
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class LauncherV3(unittest.TestCase):
 def test_failure_gate_and_readonly_task(self):
  p=B/"start-newbase-contactinfo-metadata-readonly-v3.ps1";s=p.read_text("ascii")
  for x in ("MspNewbasePhoneMetadataProbeV3",
    "MspNewbasePhoneMetadataProbeV3",
    "STATUS=FAIL;PHASE=PARSE_CONTACTINFO_METADATA;GATE=RUNTIME_ERROR;EXCEPTION_TYPE=RuntimeException;ERROR_ID=TypeNotFound;ERROR_LINE=42",
    "V2_FAILURE_RECEIPT_CHANGED","V2_TASK_NOT_IDLE",
    "PHONE_V3_SAFE_RETRY_GATE=PASS",
    "customer-phone-contactinfo-metadata-v3.txt",
    "probe-newbase-contactinfo-metadata-readonly-v3.ps1",
    "6ed341258210ad224f81db714f6c78c83a98cba3",
    "9dfd2a10cf67e91cb23ecfcfa5420d8f21ac1f58fcdbaa1d1d3e82f4e8c96040",
    "6433:6433:0","AUTO_UPDATE=OFF",
    "PHONE_METADATA_READONLY_V3_ACCEPTED",
    "PHONE_METADATA_READONLY_V3_AWAITING_RECEIPT","catch [IO.IOException]"):
   self.assertIn(x,s)
  for x in ("DeleteTask(","Triggers.Create","Remove-Item","crm.item.add?",
            "crm.item.update?","D:\\DATA\\WorkBase"):
   self.assertNotIn(x,s)
  self.assertNotIn("\r",s)
  print("PHONE_METADATA_V3_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

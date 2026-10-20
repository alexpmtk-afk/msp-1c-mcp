"""Initial 6433-mapped gate and readonly one-shot phone metadata runner."""
import unittest,hashlib
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class PhoneRunner(unittest.TestCase):
 def test_safe_live_runner(self):
  p=B/"start-newbase-contactinfo-metadata-readonly-v1.ps1"
  s=p.read_text("ascii")
  for token in ("6433:6433:0","IMPORT_NOT_FINAL","PASS_WITH_FIELD_REVIEW",
                "MspNewBaseInitialImportV5","MspNewbasePhoneMetadataProbeV1",
                "PHONE_METADATA_WORKER_SHA256=PASS",
                "2c06a6e9148e10c420aab77f6e7034b4e3eb0c30f91ea06627938a21a1ac8e01",
                "0da5d9a1a9713ca8abedcf271bfd4eea4190ccf8",
                "PHONE_METADATA_READONLY_ACCEPTED","PHONE_METADATA_READONLY_AWAITING_RECEIPT",
                "METADATA_GET_ONLY","CUSTOMER_EXPORT=0","BITRIX_REQUESTS=0",
                "AUTO_UPDATE=OFF","RegisterTaskDefinition"):
   if token=="Task":continue
   if token=="$":continue
   self.assertIn(token,s)
  for denied in ("Triggers.Create","crm.item.add?","crm.item.update?",
                 "DeleteTask(","Remove-Item","D:\\DATA\\WorkBase"):
   self.assertNotIn(denied,s)
  self.assertNotIn("\r",s)
  print("PHONE_METADATA_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

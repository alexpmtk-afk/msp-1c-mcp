"""V2 phone coverage safe one-time launcher after exact V1 count-negotiation failure."""
import hashlib,unittest
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class CoverageLauncherV2(unittest.TestCase):
 def test_recovery_contract(self):
  p=B/"start-newbase-phone-coverage-readonly-v2.ps1";s=p.read_text("ascii")
  for token in ("MspNewbasePhoneCoverageReadOnlyV1",
        "MspNewbasePhoneCoverageReadOnlyV2",
        "STATUS=FAIL;SOURCE=TEST_NEWBASE;PHASE=CONTACT_COUNT_BEFORE;GATE=HTTP_406;PII_EXPORTED=0",
        "V1_FAILURE_RECEIPT_CHANGED","V1_TASK_NOT_IDLE",
        "PHONE_COVERAGE_V2_RECOVERY_GATE=PASS",
        "6433:6433:0","PHONE_COVERAGE_SAFE_GATE=PASS",
        "customer-phone-coverage-readonly-v2.txt",
        "audit-newbase-phone-coverage-readonly-v2.ps1",
        "0c7726725d03b8d6f1092617280bf8770df08111",
        "c48effdfe507364cbb9cca45344b0184f4445a63c888fe2bb20725eadef5d2c1",
        "AUTO_UPDATE=OFF","TRIGGERS_NOT_ZERO","PT45M",
        "COVERAGE_DATA_EXPORTED=NO"):
   self.assertIn(token,s)
  for denied in ("Triggers.Create","crm.item.add?","crm.item.update?","DeleteTask(",
                 "Remove-Item","D:\\DATA\\WorkBase"):
   self.assertNotIn(denied,s)
  self.assertNotIn("\r",s)
  print("PHONE_COVERAGE_V2_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__": unittest.main()

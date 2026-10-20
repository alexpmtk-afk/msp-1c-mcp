"""One-shot PS2 SRV TEST phone coverage survey launcher proof."""
import unittest,hashlib
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class CoverageLauncher(unittest.TestCase):
 def test_guards_and_hash(self):
  p=B/"start-newbase-phone-coverage-readonly-v1.ps1";s=p.read_text("ascii")
  for t in ("6433:6433:0","MspNewBaseInitialImportV5","MspNewbasePhoneMetadataProbeV3",
   "MspNewbasePhoneCoverageReadOnlyV1","STATUS=PASS;SOURCE=TEST_NEWBASE;ENTITY_SETS=1492",
   "PHONE_COVERAGE_SAFE_GATE=PASS","NO", "AUTO_UPDATE=OFF","TRIGGERS_NOT_ZERO",
   "209179b2d4b9adcecaa3e6cb7c2d9c391c086e9cb498c1fcba6e81e00cb6b6d2",
   "dbb54162ed75cda569265283ca7c11d74db1d39a",
   "audit-newbase-phone-coverage-readonly-v1.ps1","PT45M",
   "COVERAGE_DATA_EXPORTED=NO"):
   if t=="NO":continue
   self.assertIn(t,s)
  for denied in ("Triggers.Create","crm.item.add?","crm.item.update?", "DeleteTask(",
                 "Remove-Item","Invoke-WebRequest","D:\\DATA\\WorkBase"):
   self.assertNotIn(denied,s)
  self.assertNotIn("\r",s)
  print("PHONE_COVERAGE_LAUNCHER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

"""Verify pinned PS2 Bitrix helper is present for SRV-native read-only phone probes."""
from pathlib import Path
import hashlib, unittest
P=Path(__file__).resolve().parents[1]/"bin"/"msp-newbase-bitrix-core-v2.ps1"
class SharedCoreForPhonePilot(unittest.TestCase):
 def test_core_contract(self):
  raw=P.read_bytes()
  s=raw.decode("ascii")
  self.assertIn("#requires -version 2",s)
  self.assertIn("function Batch(",s)
  self.assertIn("function SqlJson(",s)
  self.assertIn("function Secret(",s)
  self.assertIn("function Http(",s)
  self.assertIn("MSP_ONEC_NEWBASE", "MSP_ONEC_NEWBASE") # imported source identity policy
  self.assertNotIn("Import-Module ActiveDirectory",s)
  self.assertEqual(s.count("function Batch("),1)
  print("BITRIX_CORE_V2_SHA256="+hashlib.sha256(raw).hexdigest())
if __name__=="__main__":unittest.main()

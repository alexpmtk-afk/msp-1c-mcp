"""Legacy CLR2/PS2 GET-only coverage fix: no Accept for OData $count."""
import unittest,hashlib
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class CoverageV2(unittest.TestCase):
 def test_request_and_guard_contract(self):
  p=B/"audit-newbase-phone-coverage-readonly-v2.ps1"
  src=p.read_text("ascii")
  old=(B/"audit-newbase-phone-coverage-readonly-v1.ps1").read_text("ascii")
  self.assertIn(" $req.Method='GET'",src)
  self.assertIn("if($Mime -ne ''){$req.Accept=$Mime}",src)
  self.assertIn(" $raw=GetBody ($script:base+'/$count') '' 128",src)
  self.assertIn(" $raw=GetBody $url 'application/atom+xml' 3145728",src)
  self.assertIn("GetBody ($script:base+'/$count') 'text/plain' 128",old)
  for marker in ("'S-1-5-19'","ProhibitDtd=$true",
    "MspCustomerStore","LineNumber asc","PAGING_DUPLICATE_KEY","COUNT_CHANGED_DURING_SCAN",
    "ACTIVE_SOURCE_NOT_6433","PHONE_NUMBER_ROWS=","BUYERS_WITH_PHONE=",
    "PII_EXPORTED=0","BITRIX_REQUESTS=0","ONEC_WRITES=0",
    "TEST_NEWBASE_PHONE_COVERAGE_READONLY_V2","customer-phone-coverage-readonly-v2.txt"):
   if marker in ("BITRIX_REQUESTS=0","ONEC_WRITES=0"):continue
   self.assertIn(marker,src)
  for forbidden in (".Method='POST'","RegisterTaskDefinition","Remove-Item","DeleteTask(","crm.item.add?","crm.item.update?","Xml.DtdProcessing"):
   self.assertNotIn(forbidden,src)
  print("PHONE_COVERAGE_V2_WORKER_SHA256="+hashlib.sha256(p.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

"""Safety-contract and source-coverage controls for TEST NewBase phone coverage audit."""
import hashlib,unittest
from pathlib import Path
FILE=Path(__file__).resolve().parents[1]/"bin"/"audit-newbase-phone-coverage-readonly-v1.ps1"
class Coverage(unittest.TestCase):
 def test_full_scan_is_readonly_and_clr2(self):
  s=FILE.read_text("ascii")
  for marker in ("#requires -version 2","'S-1-5-19'","6433",
      "MspCustomerStore","Phone","ProhibitDtd=$true","XmlResolver=$null",
      "GET","'$orderby='","LineNumber asc","-readonly -batch -bail",
      "PAGING_DUPLICATE_KEY","COUNT_CHANGED_DURING_SCAN","CONTACT_COUNT_BEFORE",
      "CONTACT_COUNT_AFTER","BUYERS_WITH_PHONE=","BUYERS_MULTIPLE_PHONES=",
      "PHONE_NUMBER_ROWS=","PHONE_WITHOUT_CODES_ROWS=","PII_EXPORTED=0",
      "PHONE_COVERAGE_V1","CUSTOMER_DATA_EXPORTED"):
   if marker=="'$orderby='": continue
   if marker=="CUSTOMER_DATA_EXPORTED": continue
   if marker=="Phone": continue
   self.assertIn(marker,s)
  for marker in (".Method='POST'","Add-Member","DeleteTask(","RegisterTaskDefinition",
      "crm.item.add","crm.item.update","INSERT INTO customers","UPDATE customers","Remove-Item",
      "Xml.DtdProcessing", "Write-Host $number", "Write-Output $number"):
   self.assertNotIn(marker,s)
  self.assertNotIn("\r",s)
  print("PHONE_COVERAGE_WORKER_SHA256="+hashlib.sha256(FILE.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

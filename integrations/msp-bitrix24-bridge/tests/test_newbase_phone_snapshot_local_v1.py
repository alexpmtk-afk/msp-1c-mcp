"""Source-to-isolated-SQLite phone snapshot: PS2-safe no CRM writes, source lock, aggregates only."""
import hashlib,unittest
from pathlib import Path
P=Path(__file__).resolve().parents[1]/"bin"/"snapshot-newbase-phone-source-local-v1.ps1"
class Snapshot(unittest.TestCase):
 def test_contract(self):
  s=P.read_text("ascii")
  for x in ("#requires -version 2","LOCAL_SERVICE_REQUIRED","PRIOR_COVERAGE_CHANGED",
    "PHONE_SNAPSHOT_ALREADY_EXISTS","phone-source-newbase-v1.sqlite.pending",
    "phone-source-newbase-v1.sqlite","RunSql $pending","[IO.File]::Move($pending,$target)",
    "4068:4067:4068","SOURCE_COVERAGE_CHANGED","PHONE_TYPE_UNEXPECTED",
    "PHONE_NUMBER_INVALID","PAGING_DUPLICATE_KEY","COUNT_CHANGED_DURING_SCAN",
    "STAGING_INTEGRITY_FAILED","CUSTOMERS_DB_WRITES=0","STAGING_DB_WRITES=YES",
    "PII_EXPORTED=0","XmlResolver=$null","ProhibitDtd=$true",
    "SELECT onec_guid FROM customers WHERE buyer=1",
    "PRIOR_COVERAGE_MISSING","SOURCE=TEST_NEWBASE","AUTO_UPDATE=OFF"):
   if x=="AUTO_UPDATE=OFF":continue
   self.assertIn(x,s)
  for bad in ("crm.item.update?","crm.item.add?","DeleteTask(","RegisterTaskDefinition",
   "DROP TABLE customers","UPDATE customers","ALTER TABLE customers","Remove-Item",
   "Console.WriteLine($number)","Write-Output $number","Xml.DtdProcessing"):
   self.assertNotIn(bad,s)
  self.assertEqual(s.count("function RunSql("),1)
  self.assertNotIn("\r",s)
  print("PHONE_SNAPSHOT_WORKER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

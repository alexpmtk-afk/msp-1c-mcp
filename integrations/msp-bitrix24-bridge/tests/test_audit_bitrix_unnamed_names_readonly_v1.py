"""Read-only live name/source duplicate audit contract before any CRM writes."""
from pathlib import Path
import hashlib,sqlite3,tempfile,unittest
S=Path(__file__).resolve().parents[1]/"bin"/"audit-bitrix-unnamed-names-readonly-v1.ps1"
class UnnamedNameAudit(unittest.TestCase):
 def test_readonly_guardrails(self):
  txt=S.read_text("ascii")
  for term in ("#requires -version 2","LOCAL_SERVICE_ONLY","PS2_X64_ONLY","546:546:546",
    "crm.item.get?entityTypeId=3", "crm.item.list?entityTypeId=3",
    "filter[originatorId]=MSP_ONEC_NEWBASE", "filter[originId]=",
    "json_array_length", "DUPLICATE_ORIGIN=","IDENTITY_PROBLEMS=",
    "PLACEHOLDER=", "ALREADY_NAMED=", "DIFFERENT_NAME=",
    "OTHER_FIO_PARTS=","SCANNED=546","CRM_WRITES=0","ONEC_WRITES=0",
    "SQLITE_WRITES=0", "PII_EXPORTED=0","-readonly -batch -bail"):
   self.assertIn(term,txt)
  for banned in ("crm.item.update","crm.item.add","crm.item.delete",
    "INSERT INTO", "UPDATE customers", "DROP TABLE", "DELETE FROM",
    "RegisterTaskDefinition","Set-ScheduledTask","Invoke-WebRequest",
    "HttpWebRequest","Get-Content $raw","Write-Host $raw"):
   self.assertNotIn(banned,txt)
  self.assertNotIn("\r",txt)
  print("BITRIX_UNNAMED_READONLY_AUDIT_SHA256="+hashlib.sha256(S.read_bytes()).hexdigest())
 def test_source_count_546_is_exact_recoverable_persons(self):
  with tempfile.TemporaryDirectory() as d:
   conn=sqlite3.connect(str(Path(d)/"a.sqlite"))
   conn.execute("CREATE TABLE customers(onec_guid TEXT PRIMARY KEY,buyer INTEGER,invalid INTEGER,deletion_mark INTEGER,onec_type TEXT,person_name TEXT,name_full TEXT,name_short TEXT)")
   conn.execute("CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY,crm_id INTEGER,entity_kind INTEGER)")
   for i in range(546):
    conn.execute("INSERT INTO customers VALUES (?,1,0,0,'PERSON','','',?)",(f"guid{i}",f"Recovered Name {i}"))
    conn.execute("INSERT INTO msp_initial_map VALUES (?,?,3)",(f"guid{i}",i+1))
   conn.execute("INSERT INTO customers VALUES ('normal',1,0,0,'PERSON','Name','','Short')")
   conn.execute("INSERT INTO msp_initial_map VALUES ('normal',548,3)")
   cond="c.buyer=1 AND c.invalid=0 AND c.deletion_mark=0 AND c.onec_type='PERSON' AND length(trim(coalesce(c.person_name,'')))=0 AND length(trim(coalesce(c.name_full,'')))=0 AND length(trim(coalesce(c.name_short,'')))>0"
   stat=conn.execute("SELECT count(*),count(m.crm_id),count(DISTINCT m.crm_id) FROM customers c LEFT JOIN msp_initial_map m ON m.onec_guid=c.onec_guid AND m.entity_kind=3 WHERE "+cond).fetchone()
   self.assertEqual(stat,(546,546,546))
   conn.close()
if __name__=="__main__":unittest.main()

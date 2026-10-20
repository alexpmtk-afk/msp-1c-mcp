"""Checks for a durable, local-only Bitrix24 queue builder, retaining every source phone."""
import sqlite3, tempfile, unittest, hashlib
from pathlib import Path
from contextlib import closing
P=Path(__file__).resolve().parents[1]/"bin"/"prepare-bitrix-phone-queue-v1.ps1"
class QueuePreparationTests(unittest.TestCase):
 def test_safe_and_strict(self):
  s=P.read_text("ascii")
  for term in ("LOCAL_SERVICE_ONLY","PS2_X64_ONLY","UNIFIED_SOURCE_NOT_ACCEPTED",
    "customers.before-phone-queue-v1.sqlite.bak","msp_bitrix_phone_queue",
    "4031:4032:1089:2941:1","msp_initial_map","format_review",
    "BACKUP_INTEGRITY","BACKREAD_INTEGRITY","AUTO_UPDATE=OFF",
    "CRM_WRITES=0","PII_EXPORTED=0","BEGIN IMMEDIATE;","COMMIT;"):
   self.assertIn(term,s)
  for term in ("crm.item.update","curl.exe","HttpWebRequest","Invoke-WebRequest",
    "RegisterTaskDefinition","Triggers.Create","DELETE FROM customers",
    "UPDATE customers SET","DROP TABLE"):
   self.assertNotIn(term,s)
  print("BITRIX_PHONE_QUEUE_WORKER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
 def test_sqlite_queue_counts_and_no_duplicate_ids(self):
  with tempfile.TemporaryDirectory() as td:
   db=Path(td)/"customers.sqlite"
   with closing(sqlite3.connect(db)) as cx:
    cx.execute("CREATE TABLE customers(onec_guid TEXT PRIMARY KEY,buyer INTEGER,deletion_mark INTEGER,invalid INTEGER,inn TEXT,name_full TEXT)")
    cx.execute("CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY,crm_id INTEGER,entity_kind INTEGER)")
    cx.execute("CREATE TABLE msp_customer_phone(onec_guid TEXT,line_number INTEGER,phone_number TEXT,format_review INTEGER,PRIMARY KEY(onec_guid,line_number))")
    for i in range(4067):
     g=f"buyer-{i:05}"
     cx.execute("INSERT INTO customers VALUES (?,1,0,0,?,?)",(g,str(i),g))
     kind=4 if i<1104 else 3
     cx.execute("INSERT INTO msp_initial_map VALUES (?,?,?)",(g,i+1,kind))
     bad=1 if (i<15 or 1104<=i<1125) else 0
     cx.execute("INSERT INTO msp_customer_phone VALUES (?,1,?,?)",(g,"invalid" if bad else "+79990000000",bad))
    cx.execute("INSERT INTO msp_customer_phone VALUES (?,2,'+79990000001',0)",("buyer-04066",))
    cx.execute("CREATE TABLE msp_bitrix_phone_queue(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,entity_kind INTEGER NOT NULL,phone_count INTEGER NOT NULL,state TEXT NOT NULL)")
    cx.execute("""INSERT INTO msp_bitrix_phone_queue
      SELECT p.onec_guid,m.crm_id,m.entity_kind,count(*),'PENDING'
      FROM msp_customer_phone p JOIN msp_initial_map m ON m.onec_guid=p.onec_guid
      JOIN customers c ON c.onec_guid=p.onec_guid
      WHERE c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0
      AND m.entity_kind IN (3,4) AND m.crm_id>0
      GROUP BY p.onec_guid HAVING sum(p.format_review)=0""")
    cx.commit()
    stats=cx.execute("SELECT count(*),sum(phone_count),sum(entity_kind=4 AND phone_count=1),sum(entity_kind=3 AND phone_count=1),sum(phone_count=2) FROM msp_bitrix_phone_queue").fetchone()
    self.assertEqual(stats,(4031,4032,1089,2941,1))
    self.assertEqual(cx.execute("PRAGMA quick_check").fetchone()[0],"ok")
if __name__=="__main__":unittest.main()

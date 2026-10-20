"""Fail-closed contact-name correction of only a uniquely mapped 1C placeholder."""
from pathlib import Path
from contextlib import closing
import hashlib,sqlite3,tempfile,unittest
SCRIPT=Path(__file__).resolve().parents[1]/"bin"/"repair-bitrix-unnamed-name-pilot-v1.ps1"
class RepairUnnamedPilot(unittest.TestCase):
 def test_safe_contract(self):
  s=SCRIPT.read_text("ascii")
  for item in ("#requires -version 2","PS2_X64_REQUIRED","LOCAL_SERVICE_ONLY",
   "AUDIT_NOT_ACCEPTED","SCANNED=546;PLACEHOLDER=546",
   "Global\\MspBitrixNameRepairV1",
   "customers.before-unnamed-fix-v1.sqlite.bak",
   "msp_bitrix_name_fix","BACKUP_CORRUPT","CREATE UNIQUE INDEX",
   "546:1:545:0:0","PERSIST_INTENT","CRM_WRITE_ONCE",
   "CRM_INDEPENDENT_BACKREAD","BACKREAD_NAME_MISMATCH",
   "BACKREAD_CONTACT_FIELDS_CHANGED","BACKREAD_FIO_CHANGED",
   "ORIGIN_NOT_VERIFIED","TITLE_CHANGED","FIO_PARTS_ALREADY_SET",
   "PHONE_EMAIL_PRESERVED=PASS","name_short",
   "crm.item.get?entityTypeId=3&id=",
   "crm.item.update?entityTypeId=3&id=",
   "DONE","UNCERTAIN","AUTO_UPDATE=OFF","PII_EXPORTED=0"):
   self.assertIn(item,s)
  for banned in ("crm.item.add","crm.item.delete","DELETE FROM customers",
     "UPDATE customers SET","DROP TABLE","RegisterTaskDefinition",
     "Triggers.Create","Invoke-WebRequest","HttpWebRequest"):
   self.assertNotIn(banned,s)
  self.assertLess(s.index("$phase='PERSIST_INTENT'"),s.index("$phase='CRM_WRITE_ONCE'"))
  self.assertLess(s.index("$phase='CRM_WRITE_ONCE'"),s.index("$phase='CRM_INDEPENDENT_BACKREAD'"))
  self.assertEqual(s.count("$null=Batch @($command)"),1)
  self.assertNotIn("\r",s)
  print("BITRIX_UNNAMED_FIX_PILOT_WORKER_SHA256="+hashlib.sha256(SCRIPT.read_bytes()).hexdigest())
 def test_sqlite_immutable_source_and_unique_fix_queue(self):
  with tempfile.TemporaryDirectory() as td:
   db=Path(td)/"customers.sqlite"
   with closing(sqlite3.connect(db)) as c:
    c.execute("PRAGMA foreign_keys=ON")
    c.execute("CREATE TABLE customers(onec_guid TEXT PRIMARY KEY,onec_type TEXT, buyer INTEGER,invalid INTEGER,deletion_mark INTEGER,name_short TEXT,name_full TEXT,person_name TEXT,inn TEXT)")
    c.execute("CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY,crm_id INTEGER,entity_kind INTEGER)")
    for i in range(546):
     guid=f"guid-{i:06}"
     c.execute("INSERT INTO customers VALUES (?, 'PERSON',1,0,0,?,'','',?)",(guid,f"Имя {i}",str(i) if i < 100 else ""))
     c.execute("INSERT INTO msp_initial_map VALUES (?,?,3)",(guid,i+1))
    c.commit()
    before=c.execute("SELECT count(*),sum(length(name_short)>0),sum(length(inn)>0) FROM customers").fetchone()
    where="c.buyer=1 AND c.invalid=0 AND c.deletion_mark=0 AND c.onec_type='PERSON' AND length(trim(coalesce(c.person_name,'')))=0 AND length(trim(coalesce(c.name_full,'')))=0 AND length(trim(coalesce(c.name_short,'')))>0"
    c.executescript("""CREATE TABLE msp_bitrix_name_fix(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('PENDING','INTENT','DONE','UNCERTAIN')),updated_utc TEXT NOT NULL,verified_utc TEXT,FOREIGN KEY(onec_guid) REFERENCES customers(onec_guid));""")
    c.execute("INSERT INTO msp_bitrix_name_fix(onec_guid,crm_id,state,updated_utc) SELECT c.onec_guid,m.crm_id,'PENDING',datetime('now') FROM customers c JOIN msp_initial_map m ON m.onec_guid=c.onec_guid AND m.entity_kind=3 WHERE "+where)
    c.execute("CREATE UNIQUE INDEX idx_msp_bitrix_name_fix_crm ON msp_bitrix_name_fix(crm_id)")
    c.commit()
    self.assertEqual(c.execute("SELECT count(*),count(DISTINCT crm_id) FROM msp_bitrix_name_fix").fetchone(),(546,546))
    c.execute("UPDATE msp_bitrix_name_fix SET state='INTENT' WHERE onec_guid='guid-000000' AND crm_id=1 AND state='PENDING'")
    self.assertEqual(c.execute("SELECT changes()").fetchone()[0],1)
    c.execute("UPDATE msp_bitrix_name_fix SET state='INTENT' WHERE onec_guid='guid-000000' AND state='PENDING'")
    self.assertEqual(c.execute("SELECT changes()").fetchone()[0],0)
    c.execute("UPDATE msp_bitrix_name_fix SET state='DONE',verified_utc=datetime('now') WHERE onec_guid='guid-000000' AND state='INTENT'")
    self.assertEqual(c.execute("SELECT state,count(*) FROM msp_bitrix_name_fix GROUP BY state ORDER BY state").fetchall(),[("DONE",1),("PENDING",545)])
    self.assertEqual(c.execute("SELECT count(*),sum(length(name_short)>0),sum(length(inn)>0) FROM customers").fetchone(),before)
    self.assertEqual(c.execute("PRAGMA quick_check").fetchone()[0],"ok")
if __name__=="__main__":unittest.main()

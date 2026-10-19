"""Regression gates for local-only unification of confirmed SRV buyer/phone SQLite records."""
from pathlib import Path
import unittest,sqlite3,tempfile
P=Path(__file__).resolve().parents[1]/"bin"/"unify-srv-customer-phones-v1.ps1"

class UnifyPhoneSource(unittest.TestCase):
 def test_ps2_worker_restrictions(self):
  s=P.read_text("ascii")
  for item in (
   "#requires -version 2", "PS2_X64_REQUIRED", "LOCAL_SERVICE_ONLY",
   "customers.db", "phone-source-newbase-v1.sqlite",
   "msp_initial_map", "customer-phone-snapshot-v2.status",
   "customers.before-phone-unify-v1.sqlite",
   "msp_customer_phone", "format_review", "PRIMARY KEY(onec_guid,line_number)",
   "FOREIGN KEY(onec_guid) REFERENCES customers(onec_guid)",
   "BACKUP_MAIN", "BACKUP_NOT_OK", "BACKREAD_MAIN",
   "SOURCE_JOIN_NOT_ACCEPTED", "ALREADY_ATTEMPTED",
   "PRAGMA quick_check;", "BEGIN IMMEDIATE;", "COMMIT;",
   "count(DISTINCT onec_guid)", "COUNT", "4032", "36", "4068",
   "BITRIX_WRITES=0", "ONEC_WRITES=0", "AUTO_UPDATE=OFF", "PII_EXPORTED=0"):
   self.assertIn(item,s)
  for forbidden in (
   "crm.item.update", "crm.item.add", "curl.exe", "Invoke-WebRequest",
   "Invoke-RestMethod", "HttpWebRequest", "DELETE FROM customers",
   "UPDATE customers SET", "DROP TABLE", "MspCustomerStoreSync",
   "RegisterTaskDefinition", "Set-ScheduledTask"):
   self.assertNotIn(forbidden,s)
  self.assertNotIn("\r",s)
 def test_sqlite_atomic_merge_and_review(self):
  with tempfile.TemporaryDirectory() as d:
   main=Path(d)/"main.sqlite"
   src=Path(d)/"source.sqlite"
   with sqlite3.connect(main) as db:
    db.execute("CREATE TABLE customers(onec_guid TEXT PRIMARY KEY, buyer INTEGER,invalid INTEGER,deletion_mark INTEGER,name_short TEXT,inn TEXT)")
    db.execute("CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY,crm_id INTEGER,entity_kind INTEGER)")
    for k in range(4067):
     guid=f"guid-{k:06}"
     db.execute("INSERT INTO customers VALUES (?,1,0,0,?,?)",(guid,"Buyer "+str(k),"INN "+str(k)))
     db.execute("INSERT INTO msp_initial_map VALUES (?,?,4)",(guid,k+1))
   with sqlite3.connect(src) as db:
    db.execute("CREATE TABLE phone_source(onec_guid TEXT,line_number INTEGER,phone_number TEXT,source TEXT,PRIMARY KEY(onec_guid,line_number))")
    for k in range(4067):
     value="invalid" if k<36 else "+79990000000"
     db.execute("INSERT INTO phone_source VALUES (?,?,?,'TEST_NEWBASE')",(f"guid-{k:06}",1,value))
    db.execute("INSERT INTO phone_source VALUES (?,?,?,'TEST_NEWBASE')",("guid-004066",2,"+79990000001"))
   with sqlite3.connect(main) as db:
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("ATTACH DATABASE ? AS ph",("file:"+str(src)+"?mode=ro",))
    db.execute("BEGIN IMMEDIATE")
    db.execute("CREATE TABLE msp_customer_phone(onec_guid TEXT NOT NULL,line_number INTEGER NOT NULL,phone_number TEXT NOT NULL,source TEXT NOT NULL,format_review INTEGER NOT NULL CHECK(format_review IN (0,1)),PRIMARY KEY(onec_guid,line_number),FOREIGN KEY(onec_guid) REFERENCES customers(onec_guid))")
    db.execute("INSERT INTO msp_customer_phone SELECT onec_guid,line_number,phone_number,source,CASE WHEN phone_number GLOB '*[^0-9+() ./-]*' THEN 1 ELSE 0 END FROM ph.phone_source")
    db.commit()
    self.assertEqual(db.execute("SELECT count(*),count(DISTINCT onec_guid),sum(format_review) FROM msp_customer_phone").fetchone(),(4068,4067,36))
    self.assertEqual(db.execute("SELECT count(*) FROM customers WHERE name_short NOT LIKE 'Buyer %'").fetchone()[0],0)
    self.assertEqual(db.execute("PRAGMA quick_check").fetchone()[0],"ok")

if __name__=="__main__":unittest.main()

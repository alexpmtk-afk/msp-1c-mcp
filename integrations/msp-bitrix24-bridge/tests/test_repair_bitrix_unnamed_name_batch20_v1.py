"""Bounded name fix batch ensures durable intent before one REST update and card-by-card backread."""
from pathlib import Path
from contextlib import closing
import hashlib,sqlite3,tempfile,unittest
P=Path(__file__).resolve().parents[1]/"bin"/"repair-bitrix-unnamed-name-batch20-v1.ps1"
class BitrixUnnamedBatch20(unittest.TestCase):
 def test_safety_and_ps2_contract(self):
  s=P.read_text("ascii")
  for needle in (
   "#requires -version 2","LOCAL_SERVICE_ONLY","PS2_X64_REQUIRED",
   "msp-bitrix-unnamed-fix-pilot-v1.status","PILOT_NOT_ACCEPTED",
   "Global\\MspBitrixNameRepairV1","msp_bitrix_name_fix",
   "546:1:545:0:0","EXPECTED_20_NOT_FOUND","SOURCE_NAME_INVALID",
   "crm.item.get?entityTypeId=3&id=","crm.item.update?entityTypeId=3&id=",
   "ORIGIN_CHANGED","NAME_MISMATCH","FIO_PARTS_CHANGED",
   "CONTACT_FIELDS_CHANGED","COMMENTS_CHANGED","PREIMAGE_TOO_LARGE",
   "PERSIST_INTENT","CRM_WRITE_ONCE","CRM_INDEPENDENT_BACKREAD",
   "INTENT","DONE","UNCERTAIN","FINAL_COUNTS_BAD",
   "546:21:525:0:0","NEVER RETRY POST","AUTO_UPDATE=OFF",
   "PHONE_EMAIL_PRESERVED=PASS","PII_EXPORTED=0","ONEC_WRITES=0"
  ):self.assertIn(needle,s)
  for banned in ("crm.item.add","crm.item.delete","DELETE FROM customers",
                 "UPDATE customers SET","DROP TABLE","RegisterTaskDefinition",
                 "Triggers.Create","Invoke-RestMethod","Invoke-WebRequest",
                 "HttpWebRequest"):
   self.assertNotIn(banned,s)
  self.assertLess(s.index("$phase='PERSIST_INTENT'"),s.index("$phase='CRM_WRITE_ONCE'"))
  self.assertLess(s.index("$phase='CRM_WRITE_ONCE'"),s.index("$phase='CRM_INDEPENDENT_BACKREAD'"))
  self.assertEqual(s.count("$writeReply=Batch @($cmds.ToArray())"),1)
  self.assertNotIn("\r",s)
  print("BITRIX_UNNAMED_BATCH20_WORKER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
 def test_queue_transaction_and_restart_protection(self):
  with tempfile.TemporaryDirectory() as td:
   cx=sqlite3.connect(str(Path(td)/"local.db"))
   cx.execute("CREATE TABLE msp_bitrix_name_fix(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,state TEXT NOT NULL)")
   for i in range(546):cx.execute("INSERT INTO msp_bitrix_name_fix VALUES (?,?,?)",(f"buyer{i}",i+1,"DONE" if i==0 else "PENDING"))
   cx.commit()
   rows=cx.execute("SELECT onec_guid,crm_id FROM msp_bitrix_name_fix WHERE state='PENDING' ORDER BY onec_guid LIMIT 20").fetchall()
   self.assertEqual(len(rows),20)
   cx.execute("BEGIN IMMEDIATE")
   for g,id in rows:
    cx.execute("UPDATE msp_bitrix_name_fix SET state='INTENT' WHERE onec_guid=? AND crm_id=? AND state='PENDING'",(g,id))
    self.assertEqual(cx.execute("SELECT changes()").fetchone()[0],1)
   cx.commit()
   for g,id in rows:
    cx.execute("UPDATE msp_bitrix_name_fix SET state='INTENT' WHERE onec_guid=? AND state='PENDING'",(g,))
    self.assertEqual(cx.execute("SELECT changes()").fetchone()[0],0)
   for g,id in rows:
    cx.execute("UPDATE msp_bitrix_name_fix SET state='DONE' WHERE onec_guid=? AND crm_id=? AND state='INTENT'",(g,id))
   self.assertEqual(cx.execute("SELECT count(*),sum(state='DONE'),sum(state='PENDING'),sum(state='INTENT'),sum(state='UNCERTAIN') FROM msp_bitrix_name_fix").fetchone(),(546,21,525,0,0))
   self.assertEqual(cx.execute("PRAGMA quick_check").fetchone()[0],"ok")
   cx.close()
if __name__=="__main__":unittest.main()

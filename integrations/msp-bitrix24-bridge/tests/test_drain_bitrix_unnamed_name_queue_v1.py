"""Contract tests for one-shot fail-closed 525-contact Bitrix24 name queue drain."""
from pathlib import Path
import hashlib,sqlite3,tempfile,unittest
SCRIPT=Path(__file__).resolve().parents[1]/"bin"/"drain-bitrix-unnamed-name-queue-v1.ps1"
class BitrixUnnamedDrainV1(unittest.TestCase):
 def test_static_contract(self):
  s=SCRIPT.read_text("ascii")
  required=(
   "#requires -version 2","PS2_X64_REQUIRED","LOCAL_SERVICE_ONLY",
   "msp-bitrix-unnamed-fix-batch20-v1.status","BATCH20_NOT_ACCEPTED",
   "Global\\MspBitrixNameRepairV1","customers.before-unnamed-name-drain-v1.sqlite.bak",
   "BACKUP_VERIFY_FAILED","msp_bitrix_name_fix","546:21:525:0:0",
   "546:546:0:0:0","SOURCE_MAPPING_CHANGED","QUEUE_MODIFIED_EXTERNALLY",
   "PERSIST_INTENT","CRM_WRITE_ONCE","CRM_INDEPENDENT_BACKREAD",
   "NO_RETRY_NONEXISTENT","BACKREAD_MISMATCH","FM_CHANGED","COMMENTS_CHANGED",
   "FIO_CHANGED","NAME_MISMATCH","ORIGIN_CHANGED",
   "INTENT_NOT_DURABLE","PENDING","UNCERTAIN","VERIFIED=525",
   "CRM_WRITES=525","BATCHES=27","SOURCE=TEST_NEWBASE",
   "PHONE_EMAIL_PRESERVED=PASS","PII_EXPORTED=0",
   "ONEC_WRITES=0","AUTO_UPDATE=OFF","ALREADY_ATTEMPTED","Start-Sleep -Milliseconds 1700"
  )
  for token in required:
   if token=="NO_RETRY_NONEXISTENT":
    self.assertIn("do not retry after ambiguous response",s)
   else:self.assertIn(token,s,token)
  for forbidden in ("crm.item.add","crm.item.delete","UPDATE customers SET","DELETE FROM customers",
      "RegisterTaskDefinition","Triggers.Create","Set-ScheduledTask","Invoke-RestMethod",
      "Invoke-WebRequest","HttpWebRequest","DROP TABLE"):
   self.assertNotIn(forbidden,s)
  self.assertLess(s.index("$phase='PERSIST_INTENT'"),s.index("$phase='CRM_WRITE_ONCE'"))
  self.assertLess(s.index("$phase='CRM_WRITE_ONCE'"),s.index("$phase='CRM_INDEPENDENT_BACKREAD'"))
  self.assertEqual(s.count("$reply=Batch @($cmds.ToArray())"),1)
  self.assertEqual(s.count("$posted++;"),1)
  self.assertNotIn("\r",s)
  print("BITRIX_UNNAMED_DRAIN_WORKER_SHA256="+hashlib.sha256(SCRIPT.read_bytes()).hexdigest())
 def test_sqlite_invariants_for_27_batches(self):
  with tempfile.TemporaryDirectory() as td:
   cx=sqlite3.connect(str(Path(td)/"source.db"))
   cx.execute("CREATE TABLE msp_bitrix_name_fix(onec_guid TEXT PRIMARY KEY,crm_id INTEGER UNIQUE,state TEXT NOT NULL CHECK(state IN ('DONE','PENDING','INTENT','UNCERTAIN')))")
   for i in range(546):
    cx.execute("INSERT INTO msp_bitrix_name_fix VALUES (?,?,?)",(f"g{i:04}",i+1,"DONE" if i<21 else "PENDING"))
   cx.commit()
   batches=[]
   for n in range(27):
    rows=cx.execute("SELECT onec_guid,crm_id FROM msp_bitrix_name_fix WHERE state='PENDING' ORDER BY onec_guid LIMIT 20").fetchall()
    expected=min(20,525-sum(batches))
    self.assertEqual(len(rows),expected)
    cx.execute("BEGIN IMMEDIATE")
    for guid,crm in rows:
     cx.execute("UPDATE msp_bitrix_name_fix SET state='INTENT' WHERE onec_guid=? AND crm_id=? AND state='PENDING'",(guid,crm))
     self.assertEqual(cx.execute("SELECT changes()").fetchone()[0],1)
    cx.commit()
    self.assertEqual(cx.execute("SELECT count(*) FROM msp_bitrix_name_fix WHERE state='INTENT'").fetchone()[0],expected)
    for guid,crm in rows:
     cx.execute("UPDATE msp_bitrix_name_fix SET state='DONE' WHERE onec_guid=? AND crm_id=? AND state='INTENT'",(guid,crm))
    cx.commit()
    batches.append(expected)
   self.assertEqual(batches,[20]*26+[5])
   self.assertEqual(cx.execute("SELECT count(*),sum(state='DONE'),sum(state='PENDING'),sum(state='INTENT'),sum(state='UNCERTAIN') FROM msp_bitrix_name_fix").fetchone(),(546,546,0,0,0))
   self.assertEqual(cx.execute("PRAGMA quick_check").fetchone()[0],"ok")
   cx.close()
if __name__=="__main__":unittest.main()

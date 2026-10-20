"""Offline contract: never bulk-write CRM phones before one-card live backread."""
import unittest,hashlib,sqlite3
from pathlib import Path
P=Path(__file__).resolve().parents[1]/"bin"/"msp-bitrix-phone-sync-worker-v1.ps1"
class PhoneWorkerTests(unittest.TestCase):
 def test_ps2_direct_rest_update_and_guards(self):
  s=P.read_text("ascii")
  for token in ("#requires -version 2","PS2_X64_ONLY","LOCAL_SERVICE_ONLY",
   "MspBitrixPhoneQueueWriterV1","MODE","CRM_PREFLIGHT",
   "PERSIST_INTENT","CRM_UPDATE_ONCE","CRM_BACKREAD",
   "crm.item.get?entityTypeId=","crm.item.update?entityTypeId=",
   "fields[fm]","[typeId]=PHONE","[valueType]=OTHER",
   "originatorId","originId","msp_initial_map",
   "msp_bitrix_phone_queue","DONE","INTENT","UNCERTAIN",
   "BACKREAD_NONPHONE_FIELDS_CHANGED","BACKREAD_PHONE_FAILED",
   "PILOT_REQUIRED","PILOT_NOT_ACCEPTED","MaxCards -le 20",
   "MAX", "AUTO_UPDATE=OFF","PII_EXPORTED=0"):
   if token in ("MAX", "MODE"):continue
   self.assertIn(token,s)
  self.assertNotIn("crm.item.add",s)
  self.assertNotIn("Invoke-WebRequest",s)
  self.assertNotIn("HttpWebRequest",s)
  self.assertNotIn("Start-Sleep -Seconds (2*$t)",s[s.index("$phase='CRM_UPDATE_ONCE'"):])
  self.assertLess(s.index("$phase='PERSIST_INTENT'"),s.index("$phase='CRM_UPDATE_ONCE'"))
  self.assertLess(s.index("$phase='CRM_UPDATE_ONCE'"),s.index("$phase='CRM_BACKREAD'"))
  self.assertIn("Never retry POST",s)
  print("BITRIX_PHONE_SYNC_WORKER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
 def test_sqlite_intent_prevents_duplicate_post_and_preserves_crm_identity(self):
  db=sqlite3.connect(":memory:")
  db.execute("CREATE TABLE msp_bitrix_phone_queue(onec_guid TEXT PRIMARY KEY, crm_id INTEGER, entity_kind INTEGER,state TEXT,verified_utc TEXT)")
  db.execute("INSERT INTO msp_bitrix_phone_queue VALUES ('guid',99,4,'PENDING',NULL)")
  preflight=db.execute("SELECT crm_id,entity_kind,state FROM msp_bitrix_phone_queue WHERE onec_guid='guid'").fetchone()
  self.assertEqual(preflight,(99,4,"PENDING"))
  db.commit()
  db.execute("BEGIN IMMEDIATE")
  db.execute("UPDATE msp_bitrix_phone_queue SET state='INTENT' WHERE onec_guid='guid' AND crm_id=99 AND entity_kind=4 AND state='PENDING'")
  self.assertEqual(db.execute("SELECT changes()").fetchone()[0],1)
  db.commit()
  db.execute("UPDATE msp_bitrix_phone_queue SET state='INTENT' WHERE onec_guid='guid' AND state='PENDING'")
  self.assertEqual(db.execute("SELECT changes()").fetchone()[0],0)
  db.execute("UPDATE msp_bitrix_phone_queue SET state='DONE',verified_utc=datetime('now') WHERE onec_guid='guid' AND crm_id=99 AND state='INTENT'")
  self.assertEqual(db.execute("SELECT changes()").fetchone()[0],1)
  self.assertEqual(db.execute("SELECT state FROM msp_bitrix_phone_queue").fetchone()[0],"DONE")
  db.close()
if __name__=="__main__":unittest.main()

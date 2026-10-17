"""Offline safety tests: CRM identity match is not a successful customer UPDATE."""
from pathlib import Path
import sqlite3
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"

class OutboxSafetyV2(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core=(BIN/"msp-newbase-bitrix-core-v2.ps1").read_text("ascii")
        cls.pump=(BIN/"pump-newbase-bitrix-batch-v2.ps1").read_text("ascii")
        cls.refresh=(BIN/"refresh-newbase-source-v2.ps1").read_text("ascii")

    def test_existing_origin_keeps_update_durable(self):
        p=self.pump
        self.assertIn("EXISTING_ORIGIN_REQUIRES_UPDATE",p)
        self.assertIn("NeedsUpdate $item.guid $item.sourceStamp",p)
        self.assertIn("change_kind='UPDATE_REQUIRED'",p)
        self.assertIn("EXISTING_REQUIRES_UPDATE=",p)
        existing=p[p.index("$phase='EXISTING_ORIGIN_REQUIRES_UPDATE'"):]
        self.assertNotIn("MarkDone ",existing)
        self.assertNotIn("crm.item.update",p)
        self.assertNotIn("crm.requisite.update",p)
        self.assertNotIn("crm.item.delete",p)
        self.assertIn("ONEC_WRITES=NO",p.replace("SOURCE_1C_WRITES=NO","ONEC_WRITES=NO"))

    def test_outbox_marking_is_concurrent_change_safe(self):
        c=self.core
        p=self.pump
        self.assertIn("function MarkDone([string]$Guid,[int]$CrmId,[int]$Kind,[string]$ExpectedStamp)",c)
        self.assertIn("changed_utc="+(Lit $ExpectedStamp)",c)
        self.assertIn("AND change_kind='UPSERT' AND changed_utc=",c)
        self.assertIn("MarkDone $item.guid $item.crmId $item.entity $item.sourceStamp",p)
        self.assertIn("hex(CAST(o.changed_utc AS BLOB))",p)
        self.assertIn("if($v.Length -ne 7)",p)
        self.assertIn("changed_utc="+(Lit $ExpectedStamp)",p)
        self.assertIn("yyyy-MM-ddTHH:mm:ss.fffffffZ",self.refresh)

    def test_sqlite_upsert_changed_during_delivery_is_not_deleted(self):
        db=sqlite3.connect(":memory:")
        db.execute("CREATE TABLE outbox (guid TEXT PRIMARY KEY, changed_utc TEXT, kind TEXT)")
        guid="12345678-1234-1234-1234-123456789abc"
        old="2026-10-17T12:00:00.0000001Z"
        newer="2026-10-17T12:00:00.0000002Z"
        db.execute("INSERT INTO outbox VALUES(?,?,?)",(guid,old,"UPSERT"))
        db.execute("UPDATE outbox SET changed_utc=? WHERE guid=?",(newer,guid))
        db.execute("DELETE FROM outbox WHERE guid=? AND kind='UPSERT' AND changed_utc=?",(guid,old))
        self.assertEqual(1,db.execute("SELECT count(*) FROM outbox").fetchone()[0])
        db.execute("DELETE FROM outbox WHERE guid=? AND kind='UPSERT' AND changed_utc=?",(guid,newer))
        self.assertEqual(0,db.execute("SELECT count(*) FROM outbox").fetchone()[0])

    def test_new_change_requeues_pending_after_update_required(self):
        db=sqlite3.connect(":memory:")
        db.execute("CREATE TABLE outbox (guid TEXT PRIMARY KEY, changed_utc TEXT, kind TEXT)")
        guid="12345678-1234-1234-1234-123456789abc"
        db.execute("INSERT INTO outbox VALUES(?,?,?)",(guid,"2026-10-17T12:00:00.0000001Z","UPDATE_REQUIRED"))
        db.execute("INSERT INTO outbox VALUES(?,?,?) ON CONFLICT(guid) DO UPDATE SET changed_utc=excluded.changed_utc,kind=excluded.kind",(guid,"2026-10-17T12:01:00.0000001Z","UPSERT"))
        self.assertEqual(("UPSERT","2026-10-17T12:01:00.0000001Z"),db.execute("SELECT kind,changed_utc FROM outbox").fetchone())

if __name__=="__main__":
    unittest.main()

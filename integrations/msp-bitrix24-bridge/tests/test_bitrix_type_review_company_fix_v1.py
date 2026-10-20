"""Static and SQLite safety checks for the six-company REVIEW title correction."""
from pathlib import Path
import hashlib
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / "bin"
WORKER = ROOT / "repair-bitrix-type-review-companies-v1.ps1"
LAUNCHER = ROOT / "start-bitrix-type-review-company-fix-v1.ps1"


class TestReviewCompanyFixV1(unittest.TestCase):
    def test_worker_fail_closed(self):
        text = WORKER.read_text(encoding="ascii")
        self.assertIn("#requires -version 2", text)
        for part in (
            "LOCAL_SERVICE_ONLY", "PS2_X64_REQUIRED", "Global\\MspBitrixTypeReviewRepairV1",
            "TYPE_REVIEW", "6:6:6:1", "6:0:6:0:0", "6:0:0:6:0",
            "6:6:0:0:0", "msp_bitrix_type_review_fix",
            "CRM_PREIMAGE_CHANGED", "ORIGIN_LOOKUP_CHANGED", "PERSIST_INTENT",
            "CRM_WRITE_ONCE", "CRM_INDEPENDENT_BACKREAD",
            "CRM_WRITES=6", "BACKREAD=PASS", "FM_COMMENTS_ASSIGNED_PRESERVED=PASS",
            "SOURCE=TEST_NEWBASE", "PII_EXPORTED=0", "ONEC_WRITES=0",
            "AUTO_UPDATE=OFF", "STATUS=FAIL", "UNCERTAIN",
        ):
            self.assertIn(part, text)
        self.assertLess(text.index("$phase='PERSIST_INTENT'"), text.index("$phase='CRM_WRITE_ONCE'"))
        self.assertLess(text.index("$phase='CRM_WRITE_ONCE'"), text.index("$phase='CRM_INDEPENDENT_BACKREAD'"))
        self.assertEqual(text.count("$reply=Batch @($cmds.ToArray())"), 1)
        self.assertIn("crm.item.update?entityTypeId=4&id=", text)
        self.assertIn("&fields[title]=", text)
        for forbidden in (
            "crm.item.add", "crm.item.delete", "&fields[phone]", "&fields[fm]",
            "fields[name]", "DELETE FROM customers", "UPDATE customers SET",
            "odata/standard.odata", "SelectChanges", "RegisterTaskDefinition",
            "Triggers.Create", "Start-Job", "Start-ScheduledTask",
        ):
            self.assertNotIn(forbidden, text)
        self.assertEqual(text.count("UPDATE msp_bitrix_type_review_fix SET state='DONE'"), 1)
        self.assertTrue(all(ord(c) < 128 for c in text))
        self.assertNotIn("\r", text)

    def test_launcher_pins_worker_and_disallows_schedule(self):
        text = LAUNCHER.read_text(encoding="ascii")
        self.assertIn("SOURCE_REVIEW_COMPANIES=6", text)
        self.assertIn("MspBitrixTypeReviewCompanyFixV1", text)
        self.assertIn("Triggers.Count -ne 0", text)
        self.assertIn("S-1-5-19", text)
        self.assertIn("-ExecutionPolicy Bypass", text)
        self.assertIn("AUTO_UPDATE=OFF", text)
        self.assertIn("a930426c99b9edbb0657582caf1bd69398a10ae2", text)
        self.assertIn(hashlib.sha256(WORKER.read_bytes()).hexdigest(), text)
        self.assertEqual(hashlib.sha256(WORKER.read_bytes()).hexdigest(), "b4c7c6ada5f780e35986e466db5b9e9dc5ca0dfda41b3740cc6f575cde316166")
        for forbidden in ("Triggers.Create(", "Set-ExecutionPolicy -Scope LocalMachine", "crm.item.add", "crm.item.delete"):
            self.assertNotIn(forbidden, text)

    def test_six_rows_durable_queue_invariants(self):
        with tempfile.TemporaryDirectory() as td:
            db = sqlite3.connect(str(Path(td) / "data.sqlite"))
            db.execute("CREATE TABLE msp_bitrix_type_review_fix(onec_guid TEXT PRIMARY KEY,crm_id INTEGER UNIQUE NOT NULL,state TEXT NOT NULL CHECK(state IN ('PENDING','INTENT','DONE','UNCERTAIN')),updated_utc TEXT,verified_utc TEXT)")
            for i in range(6):
                db.execute("INSERT INTO msp_bitrix_type_review_fix(onec_guid,crm_id,state) VALUES (?,?,?)", (f"g{i}", 100+i, "PENDING"))
            db.commit()
            db.execute("BEGIN IMMEDIATE")
            db.execute("UPDATE msp_bitrix_type_review_fix SET state='INTENT' WHERE state='PENDING'")
            db.commit()
            self.assertEqual(db.execute("SELECT count(*) FROM msp_bitrix_type_review_fix WHERE state='INTENT'").fetchone()[0], 6)
            db.execute("UPDATE msp_bitrix_type_review_fix SET state='DONE' WHERE state='INTENT'")
            db.commit()
            counts = db.execute("SELECT count(*),sum(state='DONE'),sum(state='PENDING'),sum(state='INTENT'),sum(state='UNCERTAIN') FROM msp_bitrix_type_review_fix").fetchone()
            self.assertEqual(counts, (6, 6, 0, 0, 0))
            self.assertEqual(db.execute("PRAGMA quick_check").fetchone()[0], "ok")
            db.close()


if __name__ == "__main__":
    unittest.main()

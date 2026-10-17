"""Read-only SRV SQLite outbox aggregate audit, tested with synthetic records."""
from pathlib import Path
import re
import sqlite3
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"
SCRIPT=BIN/"audit-newbase-bitrix-outbox-v1.ps1"

class AuditOutbox(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=SCRIPT.read_text("ascii")
        m=re.search(r'\$q="(SELECT count\(\*\).*? FROM msp_auto_outbox;)"',cls.source)
        if not m: raise AssertionError("Cannot locate bounded aggregate SQL")
        cls.query=m.group(1)

    def test_safe_readonly_boundaries(self):
        s=self.source
        for token in ("#requires -version 2", "-readonly -batch -bail",
                      "PRAGMA quick_check", "msp_auto_map", "msp_auto_ops",
                      "UPDATE_REQUIRED", "HELＤ" if False else "HELD",
                      "ONEC_REQUESTS=0", "BITRIX_REQUESTS=0",
                      "CUSTOMER_DATA_EXPORTED=0", "SQLITE_INTEGRITY",
                      "RESULT=PASS;STAGE=NEWBASE_BITRIX_OUTBOX_READONLY_AUDIT"):
            self.assertIn(token,s)
        for forbidden in ("http://","https://","crm.item.add","crm.item.update",
                          "DELETE FROM","INSERT INTO","UPDATE customers",
                          "RegisterTaskDefinition","Run($null)","MspOnecHttpsAgentSystem"):
            self.assertNotIn(forbidden,s)
        self.assertNotIn("\r",s)

    def test_empty_queue_reports_six_zeros(self):
        db=sqlite3.connect(":memory:")
        db.execute("CREATE TABLE msp_auto_outbox(change_kind TEXT)")
        self.assertEqual("0:0:0:0:0:0",db.execute(self.query).fetchone()[0])

    def test_queue_reports_updates_separately(self):
        db=sqlite3.connect(":memory:")
        db.execute("CREATE TABLE msp_auto_outbox(change_kind TEXT)")
        db.executemany("INSERT INTO msp_auto_outbox VALUES(?)",
            [("UPSERT",),("UPSERT",),("UPDATE_REQUIRED",),("HELD",),("REMOVED",),("OTHER",)])
        self.assertEqual("6:2:1:1:1:1",db.execute(self.query).fetchone()[0])

if __name__=="__main__":
    unittest.main()

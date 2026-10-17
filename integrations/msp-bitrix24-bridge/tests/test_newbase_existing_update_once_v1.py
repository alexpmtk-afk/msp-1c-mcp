"""TEST-only one-customer CRM UPDATE implementation: static and SQLite safety gates."""
from pathlib import Path
import sqlite3
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"
SCRIPT=BIN/"update-newbase-existing-once-v1.ps1"

class ExistingUpdateOnce(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s=SCRIPT.read_text(encoding="ascii")

    def test_readonly_default_and_exact_test_guid_gate(self):
        s=self.s
        for needed in (
            "#requires -version 2",
            "[string]$OnecGuid='',[switch]$Apply",
            "LOCAL_SERVICE_ONLY",
            "TEST_NEWBASE",
            "GUID_REQUIRED",
            "CRM_ORIGIN_SEARCH",
            "ORIGINATOR_MISMATCH",
            "ORIGIN_GUID_MISMATCH",
            "ORIGIN_NOT_SINGLE",
            "REQUISITE_NOT_SINGLE",
            "REQUISITE_OWNER_MISMATCH",
            "SOURCE_CHANGED_BEFORE_WRITE",
            "SOURCE_CHANGED_DURING_WRITE",
            "PRIOR_CRM_WRITE_UNCERTAIN",
            "APPROVE_TEST_NEWBASE_GUID=",
            "ALLOW_ONE_UPDATE=YES",
            "if(-not $Apply)",
            "CRM_WRITES=0",
            "LOCAL_WRITES=0",
            "NEWBASE_EXISTING_UPDATE_DRYRUN_V1",
            "NEWBASE_EXISTING_UPDATE_APPLY_V1",
            "NO_BLIND_RETRY=YES",
        ):
            self.assertIn(needed,s)
        self.assertLess(s.index("if(-not $Apply)"),s.index("$phase='CRM_APPLY'"))
        self.assertLess(s.index("APPROVAL_FILE_MISSING"),s.index("$phase='CRM_APPLY'"))
        for forbidden in ("crm.item.add?", "crm.requisite.add?", "crm.item.delete",
                          "crm.requisite.delete", "RegisterTaskDefinition",
                          "D:\\DATA\\WorkBase", "http://127.0.0.1:8085"):
            self.assertNotIn(forbidden,s)
        self.assertNotIn("\r",s)

    def test_company_and_contact_fields_have_independent_write_backread(self):
        s=self.s
        for needed in (
            "crm.item.update?entityTypeId=",
            "crm.requisite.update?id=",
            "crm.requisite.get?id=",
            "crm.item.get?entityTypeId=",
            "crm.item.list?entityTypeId=",
            "RQ_COMPANY_FULL_NAME",
            "RQ_COMPANY_NAME",
            "RQ_INN",
            "NAME",
            "SPLIT_CONTACT_UNSUPPORTED",
            "LEGAL_INN_MISSING_OR_INVALID",
            "ITEM_BACKREAD_MISMATCH",
            "REQUISITE_BACKREAD_MISMATCH",
            "CRM_BACKREAD",
        ):
            self.assertIn(needed,s)
        self.assertIn("$script:writes++",s)
        self.assertIn("SqlStatus $OnecGuid 'UPDATE_SENT'",s)
        self.assertLess(s.index("SqlStatus $OnecGuid 'UPDATE_SENT'"),
                        s.index("$script:writes++"))
        self.assertLess(s.index("$phase='CRM_BACKREAD'"),
                        s.index("$phase='LOCAL_EXACT_ACK'"))

    def test_atomic_ack_fails_if_newer_version_arrived(self):
        s=self.s
        for needed in (
            "DELETE FROM msp_auto_outbox WHERE onec_guid=",
            "AND change_kind='UPDATE_REQUIRED' AND changed_utc=",
            "CREATE TEMP TABLE _ack_assert(n INTEGER NOT NULL CHECK(n=1))",
            "INSERT INTO _ack_assert SELECT changes()",
            "BEGIN IMMEDIATE;",
            "COMMIT;",
        ):
            self.assertIn(needed,s)
        db=sqlite3.connect(":memory:")
        db.execute("CREATE TABLE outbox(guid TEXT PRIMARY KEY, kind TEXT, stamp TEXT)")
        old="2026-10-17T12:00:00.0000001Z"
        fresh="2026-10-17T12:00:00.0000002Z"
        db.execute("INSERT INTO outbox VALUES('g','UPDATE_REQUIRED',?)",(old,))
        db.execute("UPDATE outbox SET stamp=?",(fresh,))
        with self.assertRaises(sqlite3.IntegrityError):
            db.executescript(
                "BEGIN IMMEDIATE;"
                "DELETE FROM outbox WHERE guid='g' AND kind='UPDATE_REQUIRED' AND stamp='"+old+"';"
                "CREATE TEMP TABLE _ack_assert(n INTEGER NOT NULL CHECK(n=1));"
                "INSERT INTO _ack_assert SELECT changes();"
                "COMMIT;"
            )
        db.rollback()
        self.assertEqual((fresh,),db.execute("SELECT stamp FROM outbox").fetchone())

    def test_synthetic_ack_new_version_rollbacks(self):
        db=sqlite3.connect(":memory:")
        db.execute("CREATE TABLE outbox(guid TEXT PRIMARY KEY, kind TEXT, stamp TEXT)")
        db.execute("CREATE TABLE mapping(guid TEXT PRIMARY KEY, crm_id INT)")
        stamp="2026-10-17T12:00:00.0000001Z"
        db.execute("INSERT INTO outbox VALUES('g','UPDATE_REQUIRED',?)",(stamp,))
        db.commit()
        db.executescript(
            "BEGIN IMMEDIATE;"
            "DELETE FROM outbox WHERE guid='g' AND kind='UPDATE_REQUIRED' AND stamp='"+stamp+"';"
            "CREATE TEMP TABLE _ack_assert(n INTEGER NOT NULL CHECK(n=1));"
            "INSERT INTO _ack_assert SELECT changes();"
            "INSERT INTO mapping VALUES('g',3);"
            "COMMIT;"
        )
        self.assertEqual(0,db.execute("SELECT count(*) FROM outbox").fetchone()[0])
        self.assertEqual(3,db.execute("SELECT crm_id FROM mapping").fetchone()[0])

if __name__=="__main__":
    unittest.main()

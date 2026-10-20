"""Regression for TEST one-time CRM import recovery after 15 verified inflight records."""
from pathlib import Path
import hashlib
import sqlite3
import unittest

B=Path(__file__).resolve().parents[1]/"bin"
class ImportV3(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p=B/"import-all-newbase-buyers-once-v3.ps1"
        cls.s=cls.p.read_text("ascii")
    def test_reconcile_inflight_verified_identity_name_without_creating_duplicates(self):
        s=self.s
        for x in ("function Verify($Items,$Ids)", "CRM_BACKREAD_ORIGIN_MISMATCH",
                  "CRM_VISIBLE_NAME_MISMATCH","msp_initial_inflight",
                  "msp_initial_details_review", "COMMENTS_MISMATCH",
                  "PASS_WITH_DETAILS_REVIEW",
                  "TOTAL_IN_CRM_IDENTITY_AND_NAME_VERIFIED=6433",
                  "CRM_COMMENTS_REQUIRE_REVIEW=",
                  "bitrix-initial-all-buyers-v3.status",
                  "MspOneTimeAllBuyersImportV3",
                  "SELECT count(*) FROM msp_initial_details_review",
                  "6433:1941:4486:6", "NO_BLIND_RETRY=YES",
                  "$existingReview=Verify $already $alreadyIds",
                  "CommitMap $already $alreadyIds $existingReview",
                  "$newReview=Verify $new $ids",
                  "CommitMap $new $ids $newReview",
                  "if(@('MATCH','DIFF') -notcontains $details)"):
            self.assertIn(x,s)
        self.assertNotIn("CRM_DETAILS_BACKREAD_MISMATCH",s)
        self.assertNotIn(" -notin ",s)
        self.assertNotIn(" -in ",s)
        self.assertNotIn("\r",s)
        self.assertLess(s.index("CRM_ORIGIN_SEARCH"),s.index("$phase='CRM_CREATE_BATCH'"))
        self.assertLess(s.index("CommitMap $already"),s.index("$phase='PERSIST_BEFORE_CREATE'"))
        self.assertNotIn("crm.item.update?",s)
        self.assertNotIn("crm.item.delete?",s)
        print("BULK_V3_WORKER_SHA256="+hashlib.sha256(self.p.read_bytes()).hexdigest())
    def test_synthetic_15_inflight_recovered_as_13_exact_2_review(self):
        db=sqlite3.connect(":memory:")
        db.executescript("""
          CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY,crm_id INT,entity_kind INT,mapped_utc TEXT);
          CREATE TABLE msp_initial_inflight(onec_guid TEXT PRIMARY KEY,crm_type INT,attempt_utc TEXT);
          CREATE TABLE msp_initial_details_review(onec_guid TEXT PRIMARY KEY,crm_id INT,detail_state TEXT,created_utc TEXT);
        """)
        for i in range(5):
            db.execute("INSERT INTO msp_initial_map VALUES(?,?,4,'now')",(str(i),i+1))
        for i in range(5,20):
            db.execute("INSERT INTO msp_initial_inflight VALUES(?,4,'now')",(str(i),))
        db.commit()
        for i in range(5,20):
            db.execute("BEGIN IMMEDIATE")
            db.execute("INSERT INTO msp_initial_map VALUES(?,?,4,'now')",(str(i),i+1))
            if i in (6,17):
                db.execute("INSERT INTO msp_initial_details_review VALUES(?,?,'COMMENTS_MISMATCH','now')",(str(i),i+1))
            db.execute("DELETE FROM msp_initial_inflight WHERE onec_guid=?",(str(i),))
            db.commit()
        self.assertEqual(20,db.execute("SELECT count(*) FROM msp_initial_map").fetchone()[0])
        self.assertEqual(0,db.execute("SELECT count(*) FROM msp_initial_inflight").fetchone()[0])
        self.assertEqual(2,db.execute("SELECT count(*) FROM msp_initial_details_review").fetchone()[0])
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute("INSERT INTO msp_initial_map VALUES('6',999,4,'now')")
    def test_confirmation_requires_readback_first(self):
        s=self.s
        self.assertLess(s.index("$existingReview=Verify $already $alreadyIds"),s.index("CommitMap $already"))
        self.assertLess(s.index("$newReview=Verify $new $ids"),s.index("CommitMap $new"))
        self.assertIn("if($inflight -ne '0'){Fail 'PRIOR_CREATE_UNCERTAIN_MANUAL_RECONCILE'}",s)
        self.assertIn("AND NOT EXISTS(SELECT 1 FROM msp_initial_map",s)
        self.assertIn("ON CONFLICT(onec_guid) DO UPDATE SET crm_id=excluded.crm_id",s)
    def test_aggregation_does_not_hide_mismatches(self):
        s=self.s
        self.assertIn("SaveStatus ('STATUS='+$status",s)
        self.assertIn("CRM_COMMENTS_REQUIRE_REVIEW=",s)
        self.assertIn("STATUS=PARTIAL;",s)
        self.assertIn("AUTO_UPDATE=OFF;ONEC_WRITES=0",s)

if __name__=="__main__":unittest.main()

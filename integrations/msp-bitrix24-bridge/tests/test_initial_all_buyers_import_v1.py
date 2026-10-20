"""Offline safety proof for one-time full 1C TEST buyer population CRM import."""
from pathlib import Path
import sqlite3
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"
SCRIPT=BIN/"import-all-newbase-buyers-once-v1.ps1"

class FullPopulation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s=SCRIPT.read_text(encoding="utf-8")
    def test_exact_population_including_all_six_uncategorized(self):
        s=self.s
        for needle in (
            "6433:1941:4486:6",
            "@('LEGAL','PERSON','REVIEW')",
            "$kind=if($category -eq 'PERSON'){3}else{4}",
            "[1C TYPE REVIEW]",
            "SOURCE=TEST_NEWBASE",
            "SOURCE_POPULATION_CHANGED",
            "ONEC_WRITES=0",
            "AUTO_UPDATE=OFF",
            "TARGET=6433",
            "TOTAL_IN_CRM_VERIFIED=6433",
            "fields[comments]",
            "FullName=",
            "INN=",
            "CRM_DETAILS_BACKREAD_MISMATCH",
        ):
            self.assertIn(needle,s)
    def test_no_1c_or_recurring_scheduler(self):
        s=self.s
        for forbidden in (
            "http://127.0.0.1:8085","https://vm-817589",
            "RegisterTaskDefinition", "Triggers.Create(",
            "crm.item.delete", "crm.requisite.delete",
            "crm.item.update", "crm.requisite.update",
            "msp-newbase-auto-tick",
        ):
            self.assertNotIn(forbidden,s)
        self.assertTrue(s.startswith("#requires -version 2"))
        self.assertNotIn("\r",s)
    def test_guard_against_duplicates_and_ambiguous_responses(self):
        s=self.s
        for marker in (
            "function Found(", "crm.item.list?entityTypeId=",
            "filter[originId]=", "MSP_ONEC_NEWBASE",
            "crm.item.get?entityTypeId=",
            "CRM_BACKREAD_ORIGIN_MISMATCH",
            "ORIGIN_SEARCH_AMBIGUOUS",
            "msp_initial_inflight",
            "PERSIST_BEFORE_CREATE",
            "PRIOR_CREATE_UNCERTAIN_MANUAL_RECONCILE",
            "CREATE_RESULT_AMBIGUOUS_NO_RETRY",
            "NO_BLIND_RETRY=YES",
            "Query $sql.ToString()",
            "Global\\MspOneTimeAllBuyersImportV1",
            "return ,$list", "return ,$out", "DecodeHex",
        ):
            self.assertIn(marker,s)
        self.assertLess(s.index("PERSIST_BEFORE_CREATE"),s.index("$phase='CRM_CREATE_BATCH'"))
        self.assertLess(s.index("$phase='CRM_CREATE_BACKREAD'"),s.index("CommitMap $new $ids"))
    def test_map_is_idempotent(self):
        db=sqlite3.connect(":memory:")
        db.execute("CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY,crm_id INTEGER NOT NULL,entity_kind INTEGER NOT NULL,mapped_utc TEXT NOT NULL)")
        guid="12345678-1234-1234-1234-123456789abc"
        sql=("INSERT INTO msp_initial_map VALUES(?,3,4,'2026-10-17') "
             "ON CONFLICT(onec_guid) DO UPDATE SET crm_id=excluded.crm_id,entity_kind=excluded.entity_kind,mapped_utc=excluded.mapped_utc")
        db.execute(sql,(guid,))
        db.execute(sql,(guid,))
        self.assertEqual((1,3),db.execute("SELECT count(*),crm_id FROM msp_initial_map").fetchone())
    def test_source_all_buyers_not_only_legal(self):
        db=sqlite3.connect(":memory:")
        db.execute("CREATE TABLE customers (onec_guid TEXT PRIMARY KEY,onec_type TEXT,buyer INT,deletion_mark INT,invalid INT)")
        db.execute("CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY)")
        db.executemany("INSERT INTO customers VALUES(?,?,1,0,0)",[("legal","LEGAL"),("person","PERSON"),("review","REVIEW")])
        sql=("SELECT count(*) FROM customers c WHERE buyer=1 AND deletion_mark=0 AND invalid=0 "
             "AND NOT EXISTS(SELECT 1 FROM msp_initial_map m WHERE m.onec_guid=c.onec_guid)")
        self.assertEqual(3,db.execute(sql).fetchone()[0])
        db.execute("INSERT INTO msp_initial_map VALUES('person')")
        self.assertEqual(2,db.execute(sql).fetchone()[0])

if __name__=="__main__":
    unittest.main()

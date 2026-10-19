"""New-buyer detector: no old buyer CRM backfill, no CRM/network write."""
from pathlib import Path
import sqlite3
import tempfile
import unittest

WORKER = Path(__file__).resolve().parents[1] / "bin" / "discover-newbase-new-buyers-v1.ps1"

class TestNewBuyerDiscoveryV1(unittest.TestCase):
    def test_source_read_only_and_no_legacy_outbox(self):
        s = WORKER.read_text("utf-8")
        for token in ("#requires -version 2", "SOURCE_COUNT_BEFORE", "SOURCE_COUNT_AFTER",
                      "msp_initial_map", "6433:6433:6433", "SOURCE_NEW_GUID_DIFF",
                      "SQLITE_NEW_ONLY_COMMIT", "LEFT JOIN customers",
                      "msp_newbuyer_queue", "HELD_TYPE", "PENDING",
                      "CHECK(n BETWEEN 0 AND 20)", "SQLITE_BACKREAD",
                      "BACKUP=VERIFIED", "ONEC_WRITES=0", "CRM_WRITES=0",
                      "AUTO_UPDATE=OFF", "LOCAL_SERVICE_REQUIRED", "NOT_SAFE_IDLE"):
            self.assertIn(token, s, token)
        for banned in ("msp_auto_outbox", "crm.item.add", "crm.item.update",
                       "crm.item.delete", "UPDATE customers SET",
                       "DELETE FROM customer_search_v1", "NotifyChangesReceived",
                       "SelectChanges", "RegisterTaskDefinition", "Triggers.Create"):
            self.assertNotIn(banned, s, banned)
        self.assertIn("$r.Method='GET'", s)
        self.assertNotIn("$r.Method='POST'", s)
        self.assertEqual(s.count("COMMIT;"), 1)
        self.assertEqual(s.count("INSERT INTO customers("), 1)
        self.assertEqual(s.count("INSERT INTO msp_newbuyer_queue("), 1)
        self.assertNotIn("\r", s)

    def test_sqlite_stage_only_new_guid(self):
        with tempfile.TemporaryDirectory() as td:
            db = sqlite3.connect(str(Path(td) / "data.sqlite"))
            db.executescript("""
            CREATE TABLE customers(onec_guid TEXT PRIMARY KEY, onec_type TEXT, name_short TEXT, name_full TEXT,
                person_name TEXT, inn TEXT, buyer INTEGER, deletion_mark INTEGER, invalid INTEGER,
                source_version TEXT, updated_at_utc TEXT, needs_review INTEGER);
            CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY, crm_id INTEGER UNIQUE, entity_kind INTEGER);
            CREATE TABLE customer_search_v1(onec_guid TEXT, name_short TEXT, name_full TEXT, person_name TEXT, inn TEXT);
            """)
            for i in range(6):
                guid=f"g{i}"
                db.execute("INSERT INTO customers VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    (guid,"LEGAL",f"Old {i}","", "",None,1,0,0,None,"prior",0))
                db.execute("INSERT INTO msp_initial_map VALUES (?,?,?)",(guid,100+i,4))
                db.execute("INSERT INTO customer_search_v1 VALUES (?,?,?,?,?)",(guid,f"Old {i}","","",""))
            db.commit()
            incoming=[
                ("g0","LEGAL","Old 0","","","",1,0,0,0),
                ("g1","LEGAL","Old 1","","","",1,0,0,0),
                ("new-legal","LEGAL","New Legal","New Legal","","123",1,0,0,0),
                ("new-review","REVIEW","New Review","New Review","","",1,0,0,1)
            ]
            db.execute("CREATE TEMP TABLE _incoming(onec_guid TEXT PRIMARY KEY,onec_type TEXT,name_short TEXT,name_full TEXT,person_name TEXT,inn TEXT,buyer INTEGER,deletion_mark INTEGER,invalid INTEGER,needs_review INTEGER)")
            db.executemany("INSERT INTO _incoming VALUES (?,?,?,?,?,?,?,?,?,?)", incoming)
            db.execute("CREATE TEMP TABLE _new AS SELECT i.* FROM _incoming i LEFT JOIN customers c ON c.onec_guid=i.onec_guid WHERE c.onec_guid IS NULL")
            self.assertEqual(db.execute("SELECT count(*) FROM _new").fetchone()[0],2)
            db.executescript("""
            CREATE TABLE msp_newbuyer_queue(onec_guid TEXT PRIMARY KEY,source_type TEXT,state TEXT,discovered_utc TEXT,updated_utc TEXT,crm_id INTEGER,entity_kind INTEGER);
            INSERT INTO customers SELECT onec_guid,onec_type,name_short,name_full,person_name,inn,1,0,0,NULL,'test',needs_review FROM _new;
            INSERT INTO msp_newbuyer_queue(onec_guid,source_type,state,discovered_utc,updated_utc)
                SELECT onec_guid,onec_type,CASE WHEN onec_type='REVIEW' THEN 'HELD_TYPE' ELSE 'PENDING' END,'test','test' FROM _new;
            INSERT INTO customer_search_v1(onec_guid,name_short,name_full,person_name,inn)
                SELECT onec_guid,name_short,name_full,person_name,coalesce(inn,'') FROM _new;
            """)
            self.assertEqual(db.execute("SELECT count(*) FROM msp_initial_map").fetchone()[0],6)
            self.assertEqual(db.execute("SELECT count(*) FROM customers").fetchone()[0],8)
            self.assertEqual(db.execute("SELECT state FROM msp_newbuyer_queue WHERE onec_guid='new-legal'").fetchone()[0],"PENDING")
            self.assertEqual(db.execute("SELECT state FROM msp_newbuyer_queue WHERE onec_guid='new-review'").fetchone()[0],"HELD_TYPE")
            self.assertEqual(db.execute("SELECT count(*) FROM msp_newbuyer_queue").fetchone()[0],2)
            self.assertEqual(db.execute("PRAGMA quick_check").fetchone()[0],"ok")
            db.close()

if __name__=="__main__": unittest.main()

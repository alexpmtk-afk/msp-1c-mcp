"""Offline safety/functional contracts for paused daily 07:45 NewBase reconciliation."""
from __future__ import annotations

import pathlib
import re
import sqlite3
import unittest

BIN = pathlib.Path(__file__).resolve().parents[1] / "bin"
SOURCE = (BIN / "daily-reconcile-newbase-buyers-v1.ps1").read_text(encoding="utf-8")
WORKER = (BIN / "daily-sync-existing-to-bitrix-v1.ps1").read_text(encoding="utf-8")
STAGE = (BIN / "stage-daily-newbase-0745-tasks-v1.ps1").read_text(encoding="utf-8")


def diff_count(old_rows, new_rows):
    """Execute the production compare predicate against a tiny independent SQLite DB."""
    m = re.search(r'\$compare="([^"]+)"', SOURCE)
    assert m is not None
    conn = sqlite3.connect(":memory:")
    conn.execute(
        "CREATE TABLE customers(onec_guid TEXT PRIMARY KEY,onec_type TEXT,name_short TEXT,"
        "name_full TEXT,person_name TEXT,inn TEXT,buyer INTEGER,deletion_mark INTEGER,"
        "invalid INTEGER,needs_review INTEGER)"
    )
    conn.execute(
        "CREATE TEMP TABLE _incoming(onec_guid TEXT PRIMARY KEY,onec_type TEXT,name_short TEXT,"
        "name_full TEXT,person_name TEXT,inn TEXT,buyer INTEGER,deletion_mark INTEGER,"
        "invalid INTEGER,needs_review INTEGER)"
    )
    conn.executemany("INSERT INTO customers VALUES (?,?,?,?,?,?,?,?,?,?)", old_rows)
    conn.executemany("INSERT INTO _incoming VALUES (?,?,?,?,?,?,?,?,?,?)", new_rows)
    conn.execute(
        "CREATE TEMP TABLE _new AS SELECT i.* FROM _incoming i "
        "LEFT JOIN customers c ON c.onec_guid=i.onec_guid WHERE c.onec_guid IS NULL"
    )
    conn.execute(
        "CREATE TEMP TABLE _changed AS SELECT i.onec_guid FROM _incoming i "
        "JOIN customers c ON c.onec_guid=i.onec_guid WHERE " + m.group(1)
    )
    conn.execute(
        "CREATE TEMP TABLE _missing AS SELECT c.onec_guid FROM customers c WHERE "
        "c.buyer=1 AND c.deletion_mark=0 AND c.invalid=0 AND "
        "NOT EXISTS(SELECT 1 FROM _incoming i WHERE i.onec_guid=c.onec_guid)"
    )
    result = tuple(
        conn.execute("SELECT count(*) FROM " + name).fetchone()[0]
        for name in ("_new", "_changed", "_missing")
    )
    conn.close()
    return result


def buyer(guid, name, buyer=1, inn="1234567890"):
    return (guid, "LEGAL", name, name, "", inn, buyer, 0, 0, 0)


class Daily0745Contracts(unittest.TestCase):
    def test_no_change_means_no_action(self):
        src = [buyer("a", "A"), buyer("b", "B")]
        self.assertEqual(diff_count(src, src), (0, 0, 0))
        self.assertIn("if(($new+$changed+$removed) -eq 0)", SOURCE)
        self.assertIn("RESULT=PASS;STAGE=MSP_DAILY_0745_IDLE_V1", SOURCE)

    def test_same_count_but_changed_fields_and_removed_detected(self):
        old = [buyer("a", "A"), buyer("b", "B"), buyer("c", "C")]
        now = [buyer("a", "A changed"), buyer("b", "B"), buyer("d", "D")]
        self.assertEqual(diff_count(old, now), (1, 1, 1))

    def test_reactivated_buyer_counted_as_change(self):
        self.assertEqual(diff_count([buyer("a", "A", buyer=0)], [buyer("a", "A")]), (0, 1, 0))

    def test_deleted_buyer_absent_from_active_source(self):
        self.assertEqual(diff_count([buyer("a", "A")], []), (0, 0, 1))

    def test_source_guard_contract(self):
        self.assertIn("Global\\MspNewbaseSnapshotScanV1", SOURCE)
        self.assertIn("COUNT_CHANGED_DURING_SCAN", SOURCE)
        self.assertIn("DUPLICATE_GUID", SOURCE)
        self.assertIn("TOO_MANY_REMOVED", SOURCE)
        self.assertIn("TOO_MANY_MODIFIED", SOURCE)
        self.assertIn("TOO_MANY_NEW", SOURCE)
        self.assertIn("MAX_REMOVED=5;MAX_NEW=20", SOURCE)
        self.assertIn("msp_daily_queue", SOURCE)
        self.assertIn("'HELD_INACTIVE'", SOURCE)
        self.assertIn("UPDATE customers SET buyer=0", SOURCE)
        self.assertNotIn("DELETE FROM customers", SOURCE)
        self.assertNotIn("msp_auto_outbox", SOURCE)

    def test_low_load_daily_scan_contract(self):
        # One GET/page (100 rows) and only two count GETs; no retry loop.
        self.assertIn("Page $filter $fetched 100 $fields", SOURCE)
        self.assertIn("Start-Sleep -Milliseconds 750", SOURCE)
        self.assertIn("'ODATA_REQUESTS='+(2+$pages)", SOURCE)
        self.assertIn("RETRIES=0", SOURCE)
        self.assertIn("$mutex.WaitOne(600000,$false)", SOURCE)
        self.assertIn("SOURCE_SCAN_BUSY_AFTER_10MIN", SOURCE)
        self.assertIn("$r.Timeout=90000", SOURCE)
        # Preview should use DEFERRED BEGIN; live local commit keeps IMMEDIATE.
        self.assertIn("$previewScript='BEGIN;'", SOURCE)
        self.assertIn("BEGIN IMMEDIATE;", SOURCE)
        self.assertIn("STATUS=FAIL;SOURCE=TEST_NEWBASE", SOURCE)

    def test_separate_crm_worker_safe_contract(self):
        self.assertIn("ALLOW_DAILY_CRM_UPDATE=YES", WORKER)
        self.assertIn("MAX_PER_RUN=1;NO_DELETE=YES", WORKER)
        self.assertIn("msp_daily_queue SET state='INTENT'", WORKER)
        self.assertIn("msp_daily_queue SET state='UNCERTAIN'", WORKER)
        self.assertIn("DAILY_UPDATE_SENT", WORKER)
        self.assertIn("crm.item.update?", WORKER)
        self.assertIn("crm.requisite.update?", WORKER)
        self.assertNotIn("crm.item.delete", WORKER)
        self.assertNotIn("crm.requisite.delete", WORKER)

    def test_schedule_is_paused_and_separate(self):
        self.assertIn("MspDailyNewbaseSource0745V1", STAGE)
        self.assertIn("MspDailyNewbaseCrmAutoV1", STAGE)
        self.assertIn("$day.AddHours(7).AddMinutes(45)", STAGE)
        self.assertIn("$day.AddHours(8)", STAGE)
        self.assertIn("$tr.Enabled=$false", STAGE)
        self.assertIn("LOCAL_SERVICE", STAGE)
        self.assertIn("CURRENT_NEWBUYER_AUTO=UNCHANGED", STAGE)


if __name__ == "__main__":
    unittest.main()

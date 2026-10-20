"""Offline execution of the actual daily reconciliation SQL against isolated SQLite fixtures.

No SRV, 1C, CRM, credentials, real buyers or network access. Read SQL lines
from the production PS2 implementation rather than reimplementing write rules.
"""
from __future__ import annotations

import re
import sqlite3
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "bin" / "daily-reconcile-newbase-buyers-v1.ps1").read_text(encoding="utf-8")
STAMP = "2026-10-20T07:45:00.0000000Z"
FIELDS = (
    "onec_guid", "onec_type", "name_short", "name_full", "person_name", "inn",
    "buyer", "deletion_mark", "invalid", "needs_review"
)
GU = lambda n: f"00000000-0000-0000-0000-{n:012x}"


def sql_statement(prefix: str, expected: int | None = None) -> str:
    """Extract one production AppendLine statement; resolve only fixed test stamp/count."""
    matches = [ln.strip() for ln in SOURCE.splitlines() if "AppendLine(" in ln and prefix in ln]
    if len(matches) != 1:
        raise AssertionError(f"ambiguous/missing production SQL for {prefix}: {len(matches)}")
    expr = matches[0].split("AppendLine(", 1)[1].rsplit(");", 1)[0]
    if "(Literal $stamp)" in expr:
        # PS2 constructs SQL from double-quoted literals separated by Literal($stamp).
        chunks = re.findall(r'"([^"]*)"', expr)
        if len(chunks) != expr.count("(Literal $stamp)") + 1:
            raise AssertionError(f"unrecognized dynamic SQL for {prefix}")
        result = ("'" + STAMP + "'").join(chunks)
    elif "$expected" in expr:
        if expected is None:
            raise AssertionError("missing expected count")
        # Only the fixed expected-count guard may interpolate $expected.
        if not expr.startswith("'CREATE TEMP TABLE _verify(n INTEGER CHECK(n='+$expected+'));"):
            raise AssertionError("unexpected dynamic expected count")
        result = expr.replace("'+$expected+'", str(expected))[1:-1]
    elif expr[0] == "'" and expr[-1] == "'":
        result = expr[1:-1]
    elif expr[0] == '"' and expr[-1] == '"':
        result = expr[1:-1]
    else:
        raise AssertionError(f"unrecognized production statement shape for {prefix}")
    if not result.endswith(";"):
        raise AssertionError(f"unterminated SQL {prefix}")
    return result


def record(n: int, name: str, *, category="LEGAL", active=True):
    guid = GU(n)
    return (guid, category, name, name + " (full)", "" if category == "LEGAL" else name,
            f"{n:010d}", int(active), 0, 0, 0)


def database(existing, maps, newbuyer_queue=None, daily_queue=None):
    db = sqlite3.connect(":memory:")
    db.executescript("""
    CREATE TABLE customers(
      onec_guid TEXT PRIMARY KEY, onec_type TEXT, name_short TEXT, name_full TEXT,
      person_name TEXT, inn TEXT, buyer INTEGER, deletion_mark INTEGER,
      invalid INTEGER, needs_review INTEGER, source_version TEXT, updated_at_utc TEXT
    );
    CREATE TABLE customer_search_v1(onec_guid TEXT PRIMARY KEY, name_short TEXT,
      name_full TEXT, person_name TEXT, inn TEXT);
    CREATE TABLE msp_initial_map(onec_guid TEXT PRIMARY KEY, crm_id INTEGER,
      entity_kind INTEGER, mapped_utc TEXT);
    CREATE TABLE msp_auto_map(onec_guid TEXT PRIMARY KEY, crm_id INTEGER,
      entity_kind INTEGER, mapped_utc TEXT);
    CREATE TABLE msp_newbuyer_queue(onec_guid TEXT PRIMARY KEY,
      source_type TEXT, state TEXT, discovered_utc TEXT, updated_utc TEXT,
      crm_id INTEGER, entity_kind INTEGER);
    """)
    for r in existing:
        db.execute("INSERT INTO customers VALUES (?,?,?,?,?,?,?,?,?,?,NULL,?)", (*r, STAMP))
        if r[6] == 1:
            db.execute("INSERT INTO customer_search_v1 VALUES (?,?,?,?,?)",
                       (r[0], r[2], r[3], r[4], r[5]))
    for n in maps:
        db.execute("INSERT INTO msp_initial_map VALUES (?,?,?,?)",
                   (GU(n), n * 100, 4, STAMP))
    for g, state in (newbuyer_queue or []):
        db.execute("INSERT INTO msp_newbuyer_queue VALUES (?,?,?,?,?,NULL,NULL)",
                   (GU(g), "LEGAL", state, STAMP, STAMP))
    if daily_queue:
        db.execute(sql_statement("CREATE TABLE IF NOT EXISTS msp_daily_queue"))
        for n, state in daily_queue:
            db.execute("INSERT INTO msp_daily_queue VALUES (?,?,?,?,?,?)",
                       (GU(n), "UPDATE", state, STAMP, n * 100, 4))
    db.commit()
    return db


def diff_sql():
    compare = re.search(r'\$compare="([^"]+)"', SOURCE)
    assert compare
    return [
        sql_statement("CREATE TEMP TABLE _new"),
        "CREATE TEMP TABLE _changed AS SELECT i.onec_guid FROM _incoming i "
        "JOIN customers c ON c.onec_guid=i.onec_guid WHERE " + compare.group(1) + ";",
        sql_statement("CREATE TEMP TABLE _missing"),
    ]


def stage_sql(active, expected):
    stmts = ["BEGIN IMMEDIATE;", sql_statement("CREATE TEMP TABLE _incoming")]
    # Read data only from isolated synthetic fixtures, not 1C or SRV.
    for r in active:
        vals = [
            "'" + v.replace("'", "''") + "'" if isinstance(v, str) else str(v)
            for v in r
        ]
        stmts.append("INSERT INTO _incoming VALUES (" + ",".join(vals) + ");")
    stmts.extend(diff_sql())
    assert len(active) == expected
    return stmts


def apply(db, active):
    initial = stage_sql(active, len(active))
    changes = [
        sql_statement("CREATE TABLE IF NOT EXISTS msp_daily_queue"),
        sql_statement("CREATE TEMP TABLE _g1"),
        sql_statement("CREATE TEMP TABLE _g2"),
        sql_statement("CREATE TEMP TABLE _g3"),
        sql_statement("CREATE TEMP TABLE _no_prior"),
        sql_statement("CREATE TEMP TABLE _no_pending_new"),
        sql_statement("INSERT INTO customers("),
        sql_statement("INSERT INTO msp_newbuyer_queue("),
        sql_statement("UPDATE customers SET onec_type="),
        sql_statement("UPDATE customers SET buyer=0"),
        sql_statement("DELETE FROM customer_search_v1"),
        sql_statement("INSERT INTO customer_search_v1("),
        sql_statement("INSERT INTO msp_daily_queue(onec_guid,kind,state,source_utc,crm_id,entity_kind) SELECT c."),
        sql_statement("INSERT INTO msp_daily_queue(onec_guid,kind,state,source_utc,crm_id,entity_kind) SELECT m."),
        sql_statement("CREATE TEMP TABLE _verify(", expected=len(active)),
        "COMMIT;",
    ]
    try:
        db.executescript("\n".join(initial + changes))
    except sqlite3.Error:
        db.rollback()
        raise


class DailyProductionSqlIntegration(unittest.TestCase):
    def test_zero_changes_produces_no_mutation(self):
        originals = [record(1, "One"), record(2, "Two")]
        db = database(originals, [1, 2])
        # Production early-return must prevent queue creation and all local writes.
        self.assertIn("if(($new+$changed+$removed) -eq 0)", SOURCE)
        self.assertEqual(db.execute("SELECT count(*) FROM sqlite_master WHERE name='msp_daily_queue'").fetchone()[0], 0)
        self.assertEqual(db.execute("SELECT count(*) FROM customers").fetchone()[0], 2)
        db.close()

    def test_one_modified_maps_to_pending_and_updates_search(self):
        originals = [record(1, "Old"), record(2, "Same")]
        new = [record(1, "New"), originals[1]]
        db = database(originals, [1, 2])
        apply(db, new)
        self.assertEqual(db.execute("SELECT name_short FROM customers WHERE onec_guid=?", (GU(1),)).fetchone()[0], "New")
        self.assertEqual(db.execute("SELECT name_short FROM customer_search_v1 WHERE onec_guid=?", (GU(1),)).fetchone()[0], "New")
        self.assertEqual(db.execute("SELECT kind,state,crm_id,entity_kind FROM msp_daily_queue").fetchall(),
                         [("UPDATE", "PENDING", 100, 4)])
        self.assertEqual(db.execute("SELECT count(*) FROM customers").fetchone()[0], 2)
        db.close()

    def test_missing_buyer_preserves_customer_mapping_and_crm(self):
        originals = [record(1, "One"), record(2, "Two")]
        db = database(originals, [1, 2])
        apply(db, [originals[0]])
        self.assertEqual(db.execute("SELECT buyer FROM customers WHERE onec_guid=?", (GU(2),)).fetchone()[0], 0)
        self.assertEqual(db.execute("SELECT count(*) FROM customer_search_v1 WHERE onec_guid=?", (GU(2),)).fetchone()[0], 0)
        self.assertEqual(db.execute("SELECT crm_id FROM msp_initial_map WHERE onec_guid=?", (GU(2),)).fetchone()[0], 200)
        self.assertEqual(db.execute("SELECT kind,state FROM msp_daily_queue").fetchall(), [("REMOVED", "HELD_INACTIVE")])
        db.close()

    def test_reactivation_adds_to_search_and_queues_update(self):
        originals = [record(1, "One", active=False), record(2, "Two")]
        db = database(originals, [1, 2])
        apply(db, [record(1, "One"), originals[1]])
        self.assertEqual(db.execute("SELECT buyer FROM customers WHERE onec_guid=?", (GU(1),)).fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT count(*) FROM customer_search_v1 WHERE onec_guid=?", (GU(1),)).fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT kind,state FROM msp_daily_queue").fetchall(), [("UPDATE", "PENDING")])
        db.close()

    def test_new_buyer_created_once_pending_only(self):
        old = record(1, "One")
        newcomer = record(3, "Three")
        db = database([old], [1])
        apply(db, [old, newcomer])
        self.assertEqual(db.execute("SELECT state FROM msp_newbuyer_queue WHERE onec_guid=?", (GU(3),)).fetchone()[0], "PENDING")
        self.assertEqual(db.execute("SELECT count(*) FROM msp_daily_queue").fetchone()[0], 0)
        self.assertEqual(db.execute("SELECT count(*) FROM customers").fetchone()[0], 2)
        db.close()

    def test_ambiguous_pending_daily_operation_aborts_atomically(self):
        old = record(1, "One")
        db = database([old], [1], daily_queue=[(1, "INTENT")])
        with self.assertRaises(sqlite3.IntegrityError):
            apply(db, [record(1, "Updated")])
        self.assertEqual(db.execute("SELECT name_short FROM customers WHERE onec_guid=?", (GU(1),)).fetchone()[0], "One")
        self.assertEqual(db.execute("SELECT state FROM msp_daily_queue").fetchone()[0], "INTENT")
        db.close()

    def test_uncertain_newbuyer_removal_aborts_atomically(self):
        a, b = record(1, "One"), record(2, "Two")
        db = database([a, b], [1, 2], newbuyer_queue=[(2, "UNCERTAIN")])
        with self.assertRaises(sqlite3.IntegrityError):
            apply(db, [a])
        self.assertEqual(db.execute("SELECT buyer FROM customers WHERE onec_guid=?", (GU(2),)).fetchone()[0], 1)
        db.close()


if __name__ == "__main__":
    unittest.main()

-- Proposed SRV-only SQLite customer index; not automatically deployed.
-- All row data remains on physical SRV. Initial population and delta are separate phases.
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS customers(
  onec_guid TEXT PRIMARY KEY CHECK(length(onec_guid)=36),
  onec_type TEXT NOT NULL CHECK(onec_type IN ('LEGAL','PERSON','REVIEW')),
  name_short TEXT NOT NULL DEFAULT '',
  name_full TEXT NOT NULL DEFAULT '',
  person_name TEXT NOT NULL DEFAULT '',
  inn TEXT,
  buyer INTEGER NOT NULL CHECK(buyer IN (0,1)),
  deletion_mark INTEGER NOT NULL CHECK(deletion_mark IN (0,1)),
  invalid INTEGER NOT NULL CHECK(invalid IN (0,1)),
  source_version TEXT,
  updated_at_utc TEXT NOT NULL,
  needs_review INTEGER NOT NULL CHECK(needs_review IN (0,1))
);
CREATE INDEX IF NOT EXISTS idx_customers_type ON customers(onec_type);
CREATE INDEX IF NOT EXISTS idx_customers_buyer ON customers(buyer,deletion_mark,invalid);
CREATE TABLE IF NOT EXISTS change_inbox(
  event_id TEXT PRIMARY KEY,
  onec_guid TEXT NOT NULL CHECK(length(onec_guid)=36),
  source_cursor TEXT NOT NULL,
  operation TEXT NOT NULL CHECK(operation IN ('UPSERT','DELETE_OR_DISABLE')),
  received_at_utc TEXT NOT NULL,
  processed_at_utc TEXT,
  state TEXT NOT NULL CHECK(state IN ('PENDING','PROCESSED','ERROR'))
);
CREATE INDEX IF NOT EXISTS idx_change_inbox_state ON change_inbox(state,received_at_utc);
CREATE TABLE IF NOT EXISTS ingestion_checkpoint(
  checkpoint_id TEXT PRIMARY KEY,
  cursor_value TEXT NOT NULL,
  committed_at_utc TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS scan_runs(
  run_id TEXT PRIMARY KEY,
  phase TEXT NOT NULL,
  status TEXT NOT NULL,
  expected_count INTEGER,
  read_count INTEGER NOT NULL DEFAULT 0,
  unique_count INTEGER NOT NULL DEFAULT 0,
  start_utc TEXT NOT NULL,
  finish_utc TEXT,
  failure_code TEXT
);

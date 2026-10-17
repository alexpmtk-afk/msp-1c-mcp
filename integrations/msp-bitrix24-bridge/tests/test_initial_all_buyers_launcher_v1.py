"""One-shot full buyer import task launcher must never affect production 1C."""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
B=ROOT/"bin"
class InitialLauncher(unittest.TestCase):
 def test_manual_task_and_pinned_bytes(self):
  s=(B/"start-initial-all-buyers-v1.ps1").read_text("ascii")
  for needle in (
    "#requires -version 2", "S-1-5-19", "S-1-5-19",
    "MspNewBaseInitialImportV1", "TASK_HAS_TRIGGERS",
    "5431a074f62a46adf4e6efa0f46a2cce1c6e6180",
    "1a80a305db4c5fa136198212c3ca8dc0e49285a5d691014cfcdd05dc36691434",
    "6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852",
    "NewTask(0)", "RegisterTaskDefinition",
    "SOURCE_SNAPSHOT_NOT_6433", "6433:1941:4486:6",
    "ExecutionTimeLimit='PT6H'", "-MaxBatches 400 -BatchSize 20",
    "STATUS_FILE=", "NO_AUTOMATIC_RETRY=YES",
    "AUTO_UPDATE=OFF",
    "INITIAL_IMPORT_TASK=STARTED"
  ):
   self.assertIn(needle,s)
  for bad in ("Triggers.Create", "DeleteTask(", "MspOnecHttpsAgentSystem", "D:\\DATA\\WorkBase", "oneC.odata", "crm.item.delete"):
   self.assertNotIn(bad,s)
  self.assertNotIn("\r",s)
 def test_workers_staged_not_overwriting_live_bins(self):
  s=(B/"start-initial-all-buyers-v1.ps1").read_text("ascii")
  self.assertIn("staging\\bitrix-initial-6433-v1",s)
  self.assertIn("STAGING_ALREADY_EXISTS",s)
  self.assertNotIn("bin\\import-all-newbase-buyers-once-v1.ps1",s)
  self.assertIn("import-all-newbase-buyers-once-v1.ps1",s)
if __name__=="__main__":unittest.main()

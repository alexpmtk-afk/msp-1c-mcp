"""V2 retry launcher accepts only source-stage V1 zero-progress failure."""
import unittest
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class LauncherV2(unittest.TestCase):
    def test_v1_failure_only_and_no_changes_to_legacy(self):
        s=(B/"start-initial-all-buyers-v2.ps1").read_text("ascii")
        for x in ("MspNewBaseInitialImportV2","MspNewBaseInitialImportV1",
                  "V1_FAILURE_RECEIPT_CHANGED",
                  "STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=READ_SOURCE_BATCH;MAPPED=0;TARGET=6433",
                  "PRIOR_CRM_OPERATION_OR_MAP_NOT_EMPTY",
                  "SELECT (SELECT count(*) FROM msp_initial_map)",
                  "msp_initial_inflight",
                  "INITIAL_V1_SAFE_RESUME_GATE=PASS",
                  "af10a1932b65bd3370785018d89f849822714e14fa55bd518c5caa026785536f",
                  "4a4664cbb3b50efe515d3bedb0bf043c066f9e78",
                  "bitrix-initial-6433-v2",
                  "bitrix-initial-all-buyers-v2.status",
                  "TaskDefinition",
                  "SOURCE_SNAPSHOT_NOT_6433",
                  "NEW_TASK_TRIGGERS=0",
                  "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(x,s)
        for x in ("Triggers.Create", "DeleteTask(", "MspOnecHttpsAgentSystem","crm.item.add?"):
            self.assertNotIn(x,s)
        self.assertNotIn("\r",s)
    def test_worker_unchanged_v1_evidence_preserved(self):
        s=(B/"start-initial-all-buyers-v2.ps1").read_text("ascii")
        self.assertIn("bitrix-initial-all-buyers-v1.status",s)
        self.assertNotIn("WriteAllText($previous",s)
        self.assertIn("GetTask('MspNewBaseInitialImportV1')",s)
        self.assertIn("GetTask($taskName)",s)

if __name__=="__main__":
    unittest.main()

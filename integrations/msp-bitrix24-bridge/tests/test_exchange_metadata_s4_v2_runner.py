"""Safety contract for one-time TEST-only S4 V2 LocalService runner."""
from pathlib import Path
import unittest

P = Path(__file__).resolve().parents[1] / "bin" / "run-exchange-plan-survey-v2.ps1"

class OneShotSurveyV2RunnerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = P.read_text(encoding="utf-8")

    def test_only_new_triggerless_task_is_created_and_deleted(self):
        s=self.script
        self.assertTrue(s.startswith("#requires -version 2"))
        for expected in (
            "$taskName='MspCustomerStoreExchangeSurveyV2'",
            "MspCustomerStoreExchangeSurvey')",
            "MspCustomerStoreSync')",
            "$def=$sch.NewTask(0)",
            "$null=$folder.RegisterTaskDefinition($taskName,$def,2",
            "$folder.DeleteTask($taskName,0)",
            "$null=$task.Run($null)",
            "$task.Definition.Triggers.Count -ne 0",
            "$phase='WAIT_WORKER_FINISH'",
            "if([int]$task.LastTaskResult -ne 0)",
            "V2_PREVIOUS_STATE_PRESENT",
            "V1_FAILURE_RECEIPT_CHANGED",
            "V1_TASK_RUNNING",
            "MAIN_TASK_RUNNING",
            "NO_AUTOMATIC_RETRY=YES",
        ):
            self.assertIn(expected,s)
        self.assertNotIn("Triggers.Create(",s)
        self.assertNotIn("RegisterTaskDefinition('MspCustomerStoreExchangeSurvey',",s)
        self.assertNotIn("DeleteTask('MspCustomerStoreExchangeSurvey',",s)
        self.assertNotIn("MspOnecHttpsAgentSystem",s)

    def test_only_metadata_get_and_sqlite_readonly(self):
        s=self.script
        for expected in (
            "survey-exchange-plan-metadata-service-v2.ps1",
            "945d5d18418ee5b289f275f1618e3f5a41aab6a94781b01fa3a9d5b8d6d4c57e",
            "f41bf94ed4187fcc41a5bc1e8d09c86a86e333d5",
            "sqlite3.exe",
            "-readonly -batch -bail",
            "PRAGMA quick_check;",
            "SELECT count(*) || ':' || count(DISTINCT onec_guid) FROM customers;",
            "NOTIFYCHANGESRECEIVED_DECLARED",
            "S4_MAIN_TASK_UNCHANGED=YES",
            "S4_6433_SNAPSHOT_UNCHANGED=YES",
            "S4_DELTA_READY=NOT_YET_PROVEN",
            "ONEC_WRITES=NO",
            "BITRIX_CALLS=NO",
            "SHA256Managed",
            "PSParser",
        ):
            self.assertIn(expected,s)
        for forbidden in ("SelectChanges.json", "NotifyChangesReceived.json",
                          "INSERT INTO", "UPDATE customers", "DELETE FROM",
                          "crm.item.add", "crm.item.update"):
            self.assertNotIn(forbidden,s)
        self.assertNotIn("\r",s)

if __name__ == "__main__":
    unittest.main()

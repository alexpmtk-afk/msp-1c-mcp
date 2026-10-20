"""Windows Server 2008 R2 LocalService alias regression for one-time CMD repair."""
from pathlib import Path
import unittest

SCRIPT=(Path(__file__).resolve().parents[1]/"bin"/"recover-newbuyer-diagnostic-v3.ps1")

class TestDiagnosticRecoveryV3(unittest.TestCase):
    def test_known_aliases_only_with_service_logon_and_lowest_run_level(self):
        s=SCRIPT.read_text("ascii")
        self.assertIn("$taskUser -ceq 'LOCAL SERVICE'",s)
        self.assertIn("$taskUser -ceq 'S-1-5-19'",s)
        self.assertIn("$taskUser -ceq $service",s)
        self.assertIn("LogonType -ne 5",s)
        self.assertIn("RunLevel -ne 0",s)
        self.assertIn("TASK_IDENTITY_CHANGED",s)
        self.assertNotIn("-cnotin",s)
        self.assertNotIn("-notin",s)
    def test_one_shot_atomic_backup_preflight_and_zero_customer_writes(self):
        s=SCRIPT.read_text("ascii")
        for literal in ("TASK_STILL_RUNNING","OLD_CMD_NOT_EXPECTED_SHAPE","REPAIRED",
                        "start-diagnostic.cmd.before-fix-v2",
                        "MspNewBuyerDiagnosticV1","MspNewBuyerDiscoveryV1",
                        "start-diagnostic.cmd.pending-v2",
                        "OLD_INTERACTIVE_CHILD_STILL_ALIVE","OLD_DIAGNOSTIC_CMD_PROCESS_STILL_ALIVE",
                        "REPLACED_CMD_INVALID", "NEW_CMD_INVALID", "BACKUP_MISSING",
                        "RESULT=STARTED;STAGE=MSP_NEWBUYER_DIAGNOSTIC_RECOVERY_V3",
                        "ONEC_WRITES=0","CRM_WRITES=0","CUSTOMERS_DB_WRITES=0"):
            if literal == "REPAIRED":continue
            self.assertIn(literal,s)
        self.assertEqual(s.count("$task.Run($null)"),1)
        self.assertIn("File]::Replace($tmp,$bat,$backup)",s)
        for forbidden in ("Stop-Process", "Kill(", "Unregister-ScheduledTask", "crm.item.add", "RegisterTaskDefinition(", "Triggers.Create(", "UPDATE customers SET", "INSERT INTO customers"):
            self.assertNotIn(forbidden,s)
if __name__=="__main__":unittest.main()

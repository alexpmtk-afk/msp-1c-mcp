"""Offline safety contracts for diagnosis of missing NewBuyer discovery receipt."""
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1] / "bin"
WORKER = BASE / "diagnose-newbuyer-execution-v1.ps1"
START = BASE / "start-newbuyer-diagnostic-v1.ps1"

class TestNewbuyerDiagnosticV1(unittest.TestCase):
    def test_worker_is_readonly_with_explicit_stages(self):
        script=WORKER.read_text(encoding="ascii")
        for expected in ("#requires -version 2","IDENTITY=LOCAL_SERVICE;PS2_X64=PASS",
                         "OLD_WORKER_READ=PASS;HASH=PASS;PS2_PARSE=PASS",
                         "SQLITE_READ","ODATA_AUTH","ODATA_COUNT_ONLY",
                         "ODATA_WEB_STATUS","ODATA_HTTP_STATUS",
                         "msp-newbuyer-diagnostic-v1.status",
                         "ONEC_WRITES=0","CRM_WRITES=0","SQLITE_WRITES=0",
                         "AUTO_UPDATE=OFF","RESULT=FAIL;STAGE=MSP_NEWBUYER_DIAGNOSTIC_V1",
                         "RESULT=PASS;STAGE=MSP_NEWBUYER_DIAGNOSTIC_V1",
                         "http://127.0.0.1:8085/NewBase/odata/standard.odata/"):
            self.assertIn(expected,script)
        for forbidden in ("crm.item.add","crm.item.update","crm.item.delete",
                          "DELETE FROM customers","UPDATE customers SET",
                          "INSERT INTO customers","NotifyChangesReceived",
                          "SelectChanges","method='POST'","Method='POST'",
                          "Trigger.Create","RegisterTaskDefinition"):
            self.assertNotIn(forbidden,script)
        self.assertIn("msp_initial_map",script)
        self.assertIn("PRAGMA quick_check;",script)
        self.assertIn("-readonly -batch -bail",script)
    def test_launcher_is_no_trigger_and_captures_exit(self):
        script=START.read_text(encoding="ascii")
        for expected in ("#requires -version 2","MspNewBuyerDiagnosticV1",
                        "MspNewBuyerDiscoveryV1","S-1-5-19",
                        "msp-newbuyer-diagnostic-v1.stdout.txt",
                        "cmd.exe","TASK_ACTION_EXIT=",
                        "Triggers.Count -ne 0","-ExecutionPolicy Bypass",
                        "f9bc8f9ac65025b6b5d5eee6737f060e6ef00a2f72a5b4f41519d4693e16fe60"):
            self.assertIn(expected,script)
        for forbidden in ("Triggers.Create(", "Start-ScheduledTask", "Get-WinEvent",
                          "crm.item.add","NotifyChangesReceived"):
            self.assertNotIn(forbidden,script)
if __name__=="__main__": unittest.main()

"""Protect against PowerShell 2 argument splitting in the newbuyer diagnostic batch wrapper."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]/"bin"
LAUNCHER=ROOT/"start-newbuyer-diagnostic-v1.ps1"
RECOVERY=ROOT/"recover-newbuyer-diagnostic-v2.ps1"

class TestNewbuyerDiagnosticCmdRecovery(unittest.TestCase):
    def test_future_launcher_builds_atomic_lines(self):
        s=LAUNCHER.read_text(encoding="ascii")
        self.assertIn("New-Object 'System.Collections.Generic.List[string]'",s)
        self.assertIn("$lines.Add($line)",s)
        self.assertIn("$lines.Add($rcLine)",s)
        self.assertIn("$lines.ToArray()",s)
        self.assertIn("$actual.Length -ne 6",s)
        self.assertIn("CMD_LINE_INTEGRITY_FAILED",s)
        self.assertNotIn("$lines=@('@echo off'",s)

    def test_recovery_backup_exact_preimage_and_only_task_reuse(self):
        s=RECOVERY.read_text(encoding="ascii")
        for text in (
            "#requires -version 2","MspNewBuyerDiagnosticV1","MspNewBuyerDiscoveryV1",
            "GetFolder('\\')", "TASK_STILL_RUNNING", "TASK_IDENTITY_CHANGED",
            "TASK_ACTION_CHANGED", "OLD_CMD_NOT_EXPECTED_SHAPE", "OLD_INTERACTIVE_CHILD_STILL_ALIVE",
            "OLD_DIAGNOSTIC_CMD_PROCESS_STILL_ALIVE", "REPAIR_CMD", "START_ONCE",
            "File]::Replace($tmp,$bat,$backup)", "LINES=6", "CMD_REPAIR=PASS",
            "NEW_CMD_INVALID", "REPLACED_CMD_INVALID", "OLD_WORKER_HASH_CHANGED",
            "ONEC_WRITES=0", "CRM_WRITES=0", "CUSTOMERS_DB_WRITES=0",
        ):
            self.assertIn(text,s,text)
        self.assertIn("S-1-5-19",s)
        self.assertEqual(s.count("$task.Run($null)"),1)
        for forbidden in ("RegisterTaskDefinition(","Triggers.Create(","Get-WinEvent","Set-ExecutionPolicy -Scope LocalMachine",
            "Stop-Process","Win32_Process.Terminate","crm.item.add","crm.item.update","UPDATE customers SET",
            "DeleteTask(", "Unregister-ScheduledTask"):
            self.assertNotIn(forbidden,s,forbidden)
        self.assertTrue(s.isascii())
if __name__=="__main__":unittest.main()

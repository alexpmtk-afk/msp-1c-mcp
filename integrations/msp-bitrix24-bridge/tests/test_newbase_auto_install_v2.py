"""The daily TEST-NewBase automation is gated behind a LocalService acceptance run."""
import unittest
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class InstallAndTick(unittest.TestCase):
    def test_tick_is_0830_and_fast_count(self):
        s=(B/"msp-newbase-auto-tick-v2.ps1").read_text("ascii")
        for x in ("AddHours(8).AddMinutes(30)","TotalMinutes -ge 15",
                  "BUYER_COUNT_CHANGED","Worker $count","Worker $scan",
                  "Worker $pump","MaxBatchesPerTick=10",
                  "STATUS=PASS","MspNewbaseAutomatedTickV2",
                  "MSP_NEWBASE_AUTO_TICK_V2","LOCAL_SERVICE_ONLY"):
            self.assertIn(x,s)
        self.assertNotIn("crm.item.add",s)
    def test_installer_is_fail_closed(self):
        s=(B/"install-newbase-auto-v2.ps1").read_text("ascii")
        for x in ("#requires -version 2","SourceCommit","PINNED_COMMIT_REQUIRED",
                  "AUTOMATION_TASK_ALREADY_EXISTS","MspNewbaseAutoV2",
                  "StartBoundary=[DateTime]::Now.AddMinutes(1)",
                  "RegisterTaskDefinition","$trigger.Enabled=$false",
                  "FIRST_LOCAL_SERVICE_RUN","SOURCE_SCAN=YES",
                  "REASON=INITIAL","$ready.Triggers.Item(1).Enabled=$true",
                  "Bitrix24","LOCAL_SERVICE","08:30_SERVER_LOCAL",
                  "AUTO_START=ENABLED","AUTOMATION_MUST_STAY_DISABLED=YES",
                  "sha.ComputeHash" if False else "SHA256Managed",
                  "PSParser]::Tokenize"):
            self.assertIn(x,s)
        for bad in ("crm.item.delete","crm.requisite.delete","https://vm-817589",
                    "D:\\DATA\\WorkBase","Read-Host"):
            self.assertNotIn(bad,s)
    def test_count_probe_read_only(self):
        s=(B/"count-newbase-active-v2.ps1").read_text("ascii")
        self.assertIn("/NewBase/odata/standard.odata/",s)
        self.assertIn("/$count?$filter=",s)
        self.assertIn("MCP_OData_ReadOnly",s)
        self.assertNotIn("crm.item.add",s)
        self.assertNotIn("customer_search_v1",s)
if __name__=="__main__": unittest.main()

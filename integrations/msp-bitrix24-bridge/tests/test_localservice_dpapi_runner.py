"""Read-only one-shot LocalService DPAPI runner contract."""
from pathlib import Path
import unittest
BIN=Path(__file__).resolve().parents[1]/"bin"

class LocalServiceRunner(unittest.TestCase):
    def test_runner_zero_trigger_and_no_crm(self):
        s=(BIN/"run-bitrix-localservice-dpapi-once.ps1").read_text("ascii")
        for key in (
            "#requires -version 2",
            "ELEVATED_ADMIN_REQUIRED",
            "S-1-5-19",
            "MspCustomerStoreSync",
            "MAIN_AUTOSTART_ENABLED",
            "RegisterTaskDefinition",
            "MspBitrixLocalServiceDpapiOnce",
            "if($task.Definition.Triggers.Count -ne 0)",
            "DeleteTask($taskName,0)",
            "LOCAL_SERVICE_DPAPI_UNPROTECT=PASS",
            "LOCAL_SERVICE_SECRET_PATH_ACCESS=PASS",
            "DPAPI_UNPROTECT=PASS",
            "bitrix-localservice-dpapi-status.txt",
            "CLIENT_SECRET_NEVER_PRINTED" if False else "SECRET_PRINTED=NO",
            "TEMP_TASK_REMOVED=YES",
            "MAIN_COLLECTOR_AUTOSTART=OFF",
            "NO_AUTOMATIC_RETRY=YES",
            "BITRIX_CALLS=NO",
            "ONEC_CALLS=NO",
        ):
            self.assertIn(key,s)
        for bad in (
            "Read-Host", "crm.item.add", "crm.requisite.add",
            "Invoke-WebRequest", "ProtectedData]::Unprotect",
            "MspCustomerStoreSync',$def", "MspCustomerStoreSync',",
        ):
            self.assertNotIn(bad,s)
        self.assertEqual(s.count("$null=$task.Run($null)"),1)

if __name__=="__main__":
    unittest.main()

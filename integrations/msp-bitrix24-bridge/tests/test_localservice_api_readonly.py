"""LocalService CRM REST proof must be one-shot, read-only and use machine DPAPI."""
from pathlib import Path
import unittest

BIN = Path(__file__).resolve().parents[1] / "bin"

class LocalServiceApiReadonly(unittest.TestCase):
    def test_child_readonly_under_service(self):
        s=(BIN/"probe-bitrix-localservice-api-readonly.ps1").read_text("ascii")
        for token in (
            "#requires -version 2",
            "LOCAL_SERVICE_REQUIRED",
            "S-1-5-19",
            "bitrix-localservice-dpapi-status.txt",
            "bitrix-direct-enrolled-webhook-api-readonly-status.txt",
            "SERVICE_DPAPI_PROOF_NOT_ACCEPTED",
            "bitrix-direct-private",
            "ProtectedData]::Unprotect",
            "DataProtectionScope]::LocalMachine",
            "crm.requisite.preset.field.list.json",
            "PRESET_ID=1",
            "FIELD_COUNT=13",
            "IDENTITY=LOCAL_SERVICE",
            "LOCAL_SERVICE_API_READ=PASS",
            "WEBHOOK_SOURCE=MACHINE_DPAPI",
            "CRM_WRITES=NO",
            "ONEC_CALLS=NO",
            "CUSTOMER_DATA_EXPORTED=NO",
            "WEBHOOK_SAVED=YES_ENCRYPTED",
            "PHASE=READ_ONLY",
            "NO_AUTOMATIC_RETRY=YES",
        ): self.assertIn(token,s)
        for forbidden in ("Read-Host","Invoke-WebRequest","RegisterTaskDefinition",
                          "crm.item.add","crm.requisite.add","crm.requisite.update",
                          "crm.item.delete","crm.item.update"):
            self.assertNotIn(forbidden,s)
        self.assertEqual(s.count("HttpOnce $url $payload"),1)

    def test_parent_manual_single_run_zero_triggers(self):
        s=(BIN/"run-bitrix-localservice-api-readonly-once.ps1").read_text("ascii")
        for token in (
            "#requires -version 2",
            "ELEVATED_ADMIN_REQUIRED",
            "MspBitrixLocalServiceApiOnce",
            "MspCustomerStoreSync",
            "S-1-5-19",
            "MAIN_AUTOSTART_ENABLED",
            "MAIN_AUTOSTART_CHANGED",
            "RegisterTaskDefinition",
            "if($task.Definition.Triggers.Count -ne 0)",
            "DeleteTask($taskName,0)",
            "bitrix-localservice-api-readonly-status.txt",
            "PROBE_HASH_MISMATCH",
            "PROBE_DOWNLOAD_FAILED",
            "LOCAL_SERVICE_API_READ=PASS",
            "WEBHOOK_SOURCE=MACHINE_DPAPI",
            "CRM_WRITES=NO",
            "ONEC_CALLS=NO",
            "CUSTOMER_DATA_EXPORTED=NO",
            "TEMP_TASK_REMOVED=YES",
            "NO_AUTOMATIC_RETRY=YES",
        ): self.assertIn(token,s)
        for forbidden in ("Read-Host","crm.item.add","crm.requisite.add",
                          "Invoke-WebRequest","ProtectedData]::Unprotect"):
            self.assertNotIn(forbidden,s)
        self.assertEqual(s.count("$null=$task.Run($null)"),1)
        self.assertNotIn("MspCustomerStoreSync',$def",s)
        self.assertNotIn("__CHILD_HASH_PENDING__",s)

if __name__=="__main__":
    unittest.main()

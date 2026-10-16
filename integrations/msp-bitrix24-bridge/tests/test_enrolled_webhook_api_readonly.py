"""Read-only post-enrollment endpoint proof is isolated from old receipts."""
from pathlib import Path
import unittest
BIN=Path(__file__).resolve().parents[1]/"bin"
class EnrolledApiProof(unittest.TestCase):
    def test_isolated_post_enrollment_readonly(self):
        code=(BIN/"probe-bitrix-enrolled-webhook-api-readonly.ps1").read_text("ascii")
        for t in ("#requires -version 2","bitrix-direct-enrolled-webhook-api-readonly-status.txt",
                  "bitrix-direct-company-preset-fields-readonly-status.txt",
                  "PREVIOUS_PRESET_RECEIPT_UNEXPECTED",
                  "bitrix-direct-private","bitrix-direct-webhook.dpapi",
                  "ProtectedData]::Unprotect","DataProtectionScope]::LocalMachine",
                  "crm.requisite.preset.field.list.json",
                  "ENROLLED_WEBHOOK_API_READ=PASS",
                  "WEBHOOK_SOURCE=MACHINE_DPAPI",
                  "WEBHOOK_SAVED=YES_ENCRYPTED",
                  "CRM_WRITES=NO","ONEC_CALLS=NO","CUSTOMER_DATA_EXPORTED=NO",
                  "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(t,code)
        for bad in ("Read-Host","crm.item.add","crm.item.delete",
                    "crm.requisite.add","crm.requisite.update",
                    "Invoke-WebRequest","RegisterTaskDefinition",
                    "WriteAllText($plain"):
            self.assertNotIn(bad,code)
        self.assertEqual(code.count("HttpOnce $url $payload"),1)
if __name__=="__main__":
    unittest.main()

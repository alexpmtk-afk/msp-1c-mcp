"""V2 enrollment preserves safety with non-secret phase gates."""
from pathlib import Path
import unittest

B=Path(__file__).resolve().parents[1]/"bin"

class EnrollmentV2Contract(unittest.TestCase):
    def test_guardrails(self):
        s=(B/"enroll-bitrix-direct-webhook-v2.ps1").read_text("ascii")
        for required in (
            "#requires -version 2",
            "PRIVATE_DIRECTORY_ACL_APPLY",
            "PRIVATE_DIRECTORY_ACL_READBACK",
            "SECRET_FILE_ACL_APPLY",
            "WEBHOOK_HIDDEN_INPUT",
            "WEBHOOK_VALIDATION",
            "DPAPI_MACHINE_ENCRYPT",
            "ENCRYPTED_FILE_WRITE",
            "DPAPI_MACHINE_READBACK",
            "ENROLLMENT_RECEIPT_WRITE",
            "EXCEPTION_TYPE=",
            "TEMP_PRIVATE_DIRECTORY_REMOVED=",
            "bitrix-direct-webhook.dpapi",
            "bitrix-direct-webhook-enrolled.txt",
            "Read-Host",
            "-AsSecureString",
            "DataProtectionScope]::LocalMachine",
            "WEBHOOK_URL_PRINTED=NO",
            "COLLECTOR_AUTOSTART_UNCHANGED=YES",
            "BITRIX_CALLS=NO",
            "ONEC_CALLS=NO",
            "NO_AUTOMATIC_RETRY=YES",
            "ALREADY_ENROLLED_STOP"
        ):
            self.assertIn(required,s)
        for forbidden in (
            "RegisterTaskDefinition",
            "Invoke-WebRequest",
            "curl.exe",
            "crm.item.add",
            "crm.item.delete",
            "Write-Output $plain",
            "Write-Output $secret",
            "WriteAllText($secret,$plain",
            "OnecTest",
        ):
            self.assertNotIn(forbidden,s)
    def test_existing_probe_consumes_same_path(self):
        s=(B/"probe-bitrix-company-preset-fields-readonly.ps1").read_text("ascii")
        self.assertIn("staging\\bitrix-direct-private\\bitrix-direct-webhook.dpapi",s)
        self.assertIn("bitrix-direct-webhook-enrolled.txt",s)
        self.assertNotIn("Read-Host",s)

if __name__=="__main__":
    unittest.main()

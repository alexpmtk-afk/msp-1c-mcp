"""Bounded machine-DPAPI webhook enrollment contracts; never store plaintext."""
from pathlib import Path
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"

class WebhookEnrollmentContract(unittest.TestCase):
    def test_secret_enrollment_is_machine_encrypted_and_nonnetwork(self):
        s=(BIN/"enroll-bitrix-direct-webhook.ps1").read_text("ascii")
        for term in (
            "#requires -version 2",
            "bitrix-direct-private",
            "bitrix-direct-webhook.dpapi",
            "Read-Host",
            "-AsSecureString",
            "SecureStringToBSTR",
            "ZeroFreeBSTR",
            "ProtectedData]::Protect",
            "DataProtectionScope]::LocalMachine",
            "SetAccessRuleProtection",
            "S-1-5-19",
            "SetAccessControl",
            "WEBHOOK_URL_PRINTED=NO",
            "COLLECTOR_AUTOSTART_UNCHANGED=YES",
            "BITRIX_CALLS=NO",
            "ONEC_CALLS=NO",
            "ALREADY_ENROLLED_STOP",
        ):
            self.assertIn(term,s)
        for forbidden in (
            "Invoke-WebRequest",
            "curl.exe",
            "RegisterTaskDefinition",
            "crm.item.add",
            "crm.item.update",
            "crm.requisite.add",
            "WriteAllText($secret,$plain",
        ):
            self.assertNotIn(forbidden,s)

    def test_enrolled_probe_never_prompts_for_webhook(self):
        s=(BIN/"probe-bitrix-company-preset-fields-readonly.ps1").read_text("ascii")
        for term in (
            "bitrix-direct-webhook-enrolled.txt",
            "bitrix-direct-private",
            "ProtectedData]::Unprotect",
            "DataProtectionScope]::LocalMachine",
            "WEBHOOK_SOURCE=MACHINE_DPAPI",
            "WEBHOOK_NOT_ENROLLED",
        ):
            self.assertIn(term,s)
        self.assertNotIn("Read-Host",s)

if __name__=="__main__":
    unittest.main()

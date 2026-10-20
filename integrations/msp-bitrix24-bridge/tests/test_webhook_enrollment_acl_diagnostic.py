"""Bounded no-secret Windows ACL diagnostic for webhook enrollment."""
from pathlib import Path
import unittest

P=Path(__file__).resolve().parents[1]/"bin"/"diagnose-bitrix-webhook-enrollment-acl.ps1"

class ACLDiag(unittest.TestCase):
    def test_one_shot_diagnostic_contract(self):
        s=P.read_text("ascii")
        for term in (
            "#requires -version 2",
            "bitrix-direct-acl-test-",
            "PRIVATE_DIR_CREATE=PASS",
            "DIR_ACL_APPLY=PASS",
            "FILE_ACL_APPLY=PASS",
            "DPAPI_DUMMY_ROUNDTRIP=PASS",
            "STATE_FILE_WRITE=PASS",
            "TEMP_TEST_FILES_REMOVED=",
            "WEBHOOK_READ=NO", "WEBHOOK_SAVED=NO",
            "BITRIX_CALLS=NO", "ONEC_CALLS=NO",
            "EXCEPTION_TYPE=", "PHASE=",
            "IO.Directory]::Delete",
            "IO.File]::Delete",
            "dummy-test-value-only",
        ):
            self.assertIn(term,s)
        for term in (
            "Read-Host",
            "GetNetworkCredential",
            "crm.item.add",
            "crm.requisite.add",
            "Invoke-WebRequest",
            "RegisterTaskDefinition",
            "C:\\ProgramData\\MspCustomerStore\\data\\customers.db",
            "bitrix-direct-webhook.dpapi",
        ):
            self.assertNotIn(term,s)
if __name__=="__main__":
    unittest.main()

"""Real NewBase pilot only: one company and its requisite, never batch or write to 1C."""
from pathlib import Path
import unittest
SCRIPT=Path(__file__).resolve().parents[1]/"bin"/"transfer-real-test-newbase-company01.ps1"

class RealTestNewBasePilot(unittest.TestCase):
    def test_one_company_and_protected_webhook(self):
        s=SCRIPT.read_text("ascii")
        for t in (
            "#requires -version 2",
            "customers.db",
            "onec_type='LEGAL'",
            "needs_review=0",
            "bitrix-testnewbase-real-company-01.txt",
            "PRIOR_RUN_DIAGNOSE_FIRST",
            "bitrix-direct-webhook.dpapi",
            "ProtectedData]::Unprotect",
            "DataProtectionScope]::LocalMachine",
            "MSP_ONEC_NEWBASE",
            "DEDUPE_BY_ORIGIN",
            "DEDUPE_BY_NAME",
            "DEDUPE_BY_INN",
            "crm.item.list",
            "crm.requisite.list",
            "crm.item.add",
            "crm.requisite.add",
            "crm.item.get",
            "crm.requisite.get",
            "COMPANY_BACKREAD_FAILED",
            "REQUISITE_BACKREAD_FAILED",
            "WriteState 'BEFORE_ADD'",
            "WriteState 'BEFORE_REQUISITE'",
            "JsonQuote",
            "SOURCE_SQLITE_WRITES=NO",
            "NO_AUTOMATIC_RETRY=YES",
        ): self.assertIn(t,s)
        for forbidden in ("Read-Host","crm.item.delete","crm.requisite.delete",
                          "crm.item.update","crm.requisite.update",
                          "RegisterTaskDefinition","/worker/result",
                          "SELECT * FROM customers","Invoke-WebRequest"):
            self.assertNotIn(forbidden,s)
        self.assertEqual(s.count("Http 'crm.item.add'"),1)
        self.assertEqual(s.count("Http 'crm.requisite.add'"),1)
        self.assertEqual(s.count("$phase='DEDUPE_BY_ORIGIN'"),1)
        self.assertNotIn("STAGE=SRV_BITRIX_NEWBASE_COMPANY_CREATE_READ_DELETE",s)

if __name__=="__main__":
    unittest.main()

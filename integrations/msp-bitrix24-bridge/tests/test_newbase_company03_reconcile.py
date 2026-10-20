"""Read-only reconciliation for already-created real CRM company #3."""
from pathlib import Path
import unittest
S=(Path(__file__).resolve().parents[1]/"bin"/"reconcile-newbase-company03-readonly.ps1")
class ReconcileCompany03(unittest.TestCase):
    def test_never_reissue_crm_add(self):
        s=S.read_text("ascii")
        for marker in (
            "#requires -version 2",
            "FAIL_SQLITE_PARSE",
            "CREATED_ID=3",
            "COMPANY_3_SOURCE_MATCH=PASS",
            "SOURCE_GUID_MATCH=YES",
            "COMPANY_REQUISITES_COUNT=",
            "bitrix-testnewbase-real-company-01.txt",
            "MSP_ONEC_NEWBASE",
            "ENTITY_TYPE_ID",
            "ENTITY_ID",
            "New-Object IO.StreamReader",
            "Text.Encoding]::UTF8",
            "ProtectedData]::Unprotect",
            "crm.item.get",
            "crm.requisite.list",
            "CRM_WRITES=NO",
            "SOURCE_SQLITE_WRITES=NO",
            "NO_AUTOMATIC_RETRY=YES",
        ): self.assertIn(marker,s)
        for forbidden in ("crm.item.add", "crm.requisite.add", "crm.item.delete",
                          "crm.item.update", "crm.requisite.update",
                          "crm.requisite.delete", "RegisterTaskDefinition",
                          "Read-Host", "Invoke-WebRequest"):
            self.assertNotIn(forbidden,s)
        self.assertEqual(s.count("Http 'crm.item.get'"),1)
        self.assertEqual(s.count("Http 'crm.requisite.list'"),1)
if __name__=="__main__":
    unittest.main()

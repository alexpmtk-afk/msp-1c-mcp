"""Exactly one requisite for the existing, provenance-verified NewBase CRM company #3."""
from pathlib import Path
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"
SCRIPT=BIN/"complete-newbase-company03-requisite-once.ps1"

class ExistingCompany03Requisite(unittest.TestCase):
    def test_no_second_company_and_crm_write_bounded(self):
        s=SCRIPT.read_text("ascii")
        for marker in (
            "#requires -version 2",
            "bitrix-testnewbase-real-company-01.txt",
            "FAIL_SQLITE_PARSE",
            "CREATED_ID=3",
            "SELECT onec_guid",
            "onec_type='LEGAL'",
            "MSP_ONEC_NEWBASE",
            "JsonQuote",
            "AREADY" if False else "PRIOR_REQUISITE_ATTEMPT_DIAGNOSE_FIRST",
            "SOURCE_ROW_NOT_CONFIRMED",
            "VERIFY_COMPANY_AND_GUID",
            "VERIFY_REQUISITES_ABSENT",
            "CHECK_DUPLICATE_INN",
            "INN_REQUISITE_ALREADY_EXISTS",
            "bitrix-company03-requisite-once-status.txt",
            "Record 'BEFORE_REQUISITE_ADD'",
            "Record 'REQUISITE_CREATED'",
            "Record 'PASS'",
            "COMPANY_RECREATED=NO",
            "SOURCE_NEWBASE_WRITES=NO",
            "SOURCE_SQLITE_WRITES=NO",
            "NO_AUTOMATIC_RETRY=YES",
        ): self.assertIn(marker,s)
        for denied in (
            "crm.item.add","crm.item.update","crm.item.delete",
            "crm.requisite.update","crm.requisite.delete",
            "RegisterTaskDefinition","Read-Host","Invoke-WebRequest",
        ): self.assertNotIn(denied,s)
        self.assertEqual(s.count("Http 'crm.requisite.add'"),1)
        self.assertEqual(s.count("Http 'crm.item.get'"),1)
        self.assertEqual(s.count("Http 'crm.requisite.get'"),1)
        self.assertEqual(s.count("Http 'crm.requisite.list'"),2)
        self.assertEqual(s.count("function Record("),1)
        self.assertEqual(s.count("\ntry{\n if($env:COMPUTERNAME"),1)
        self.assertIn("Text.Encoding]::UTF8",s)
if __name__=="__main__":
    unittest.main()

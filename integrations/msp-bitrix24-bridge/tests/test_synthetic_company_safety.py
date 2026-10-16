"""Offline safeguards for a single synthetic Bitrix24 company test."""
from pathlib import Path
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"


class SyntheticCompanySafety(unittest.TestCase):
    def test_synthetic_only_and_one_shot(self):
        s=(BIN/"smoke-bitrix-direct-synthetic-company.ps1").read_text(encoding="ascii")
        for word in ("#requires -version 2", "Read-Host", "-AsSecureString",
                     "MSP_SYNTHETIC_TEST_", "MSP_SYNTHETIC_PROBE",
                     "crm.item.add", "crm.item.get", "crm.item.delete",
                     "BACKREAD_TITLE_MISMATCH", "DELETION_BACKREAD_UNCONFIRMED",
                     "PRIOR_RUN_DIAGNOSE_FIRST", "NO_AUTOMATIC_RETRY=YES",
                     "WEBHOOK_SAVED=NO", "REAL_CUSTOMERS_EXPORTED=NO",
                     "ONEC_DATABASE_WRITES=NO", "-notcontains $Method"):
            self.assertIn(word,s)
        for word in ("-notin", "Invoke-WebRequest", "ConvertFrom-Json",
                     "System.Web.Extensions", "JavaScriptSerializer",
                     "crm.contact.add", "crm.contact.delete",
                     "RegisterTaskDefinition("):
            self.assertNotIn(word,s)


if __name__=="__main__":
    unittest.main()

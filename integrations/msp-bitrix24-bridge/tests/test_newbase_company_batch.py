"""Bounded real-company batch for the TEST NewBase 1C customer snapshot only."""
from pathlib import Path
import unittest
SOURCE=Path(__file__).resolve().parents[1]/"bin"/"import-newbase-companies-batch-v1.ps1"

class NewbaseCompanyBatch(unittest.TestCase):
    def test_recoverable_bounded_creation(self):
        s=SOURCE.read_text("ascii")
        for expected in (
            "#requires -version 2","[int]$MaxRows=20",
            "$MaxRows -gt 50","6433:1941:4486:6",
            "state\\bitrix-newbase-company-v1.cursor",
            "state\\bitrix-newbase-company-v1.inflight",
            "state\\bitrix-newbase-company-v1.held",
            "state\\bitrix-newbase-company-v1.done",
            "UNRESOLVED_INFLIGHT_STOP",
            "SOURCE_COUNTS_CHANGED",
            "PRAGMA quick_check",
            "-readonly -batch -bail",
            "DataProtectionScope]::LocalMachine",
            "b24-uwmjda\\.bitrix24\\.ru",
            "onec_type='LEGAL'",
            "MSP_ONEC_NEWBASE",
            "sourceDb",
            "COMPANY_BACKREAD_MISMATCH",
            "REQUISITE_BACKREAD_MISMATCH",
            "COMPANY_ADD_UNCERTAIN",
            "REQUISITE_ADD_UNCERTAIN",
            "InFlight $guid 'BEFORE_COMPANY_ADD'",
            "InFlight $guid 'COMPANY_CREATED'",
            "InFlight $guid 'BEFORE_REQUISITE_ADD'",
            "InFlight $guid 'REQUISITE_CREATED'",
            "Cursor $guid 'PASS'",
            "CONTINUATION_CURSOR_SAVED=YES",
            "ROWS_HELD_FOR_REVIEW=",
            "ONEC_NEWBASE_WRITES=NO",
            "SOURCE_SQLITE_WRITES=NO",
            "NO_AUTOMATIC_RETRY=YES",
        ): self.assertIn(expected,s)
        for forbidden in (
            "crm.item.update","crm.item.delete","crm.requisite.update",
            "crm.requisite.delete","RegisterTaskDefinition","Read-Host",
            "Invoke-WebRequest","http://127.0.0.1:8085",
        ): self.assertNotIn(forbidden,s)
        self.assertEqual(s.count("Http 'crm.item.add'"),1)
        self.assertEqual(s.count("Http 'crm.requisite.add'"),1)
        self.assertEqual(s.count("function Cursor("),1)
        self.assertEqual(s.count("function InFlight("),1)
        self.assertEqual(s.count("\ntry{\n if($env:COMPUTERNAME"),1)

if __name__=="__main__":
    unittest.main()

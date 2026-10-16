"""CSV staging is fully local, read-only against 1C snapshot, and private."""
from pathlib import Path
import unittest
S=Path(__file__).resolve().parents[1]/"bin"/"export-bitrix-real-customers-csv.ps1"
class CustomerCsv(unittest.TestCase):
    def test_export_only_local(self):
        s=S.read_text("ascii")
        for tok in ("#requires -version 2","-readonly -batch -bail",
                    "bitrix-client-csv","companies.csv","contacts.csv",
                    "6433|1941|4486|6", "SetAccessRuleProtection($true,$false)",
                    "AreAccessRulesProtected", "Read($buf,0,$buf.Length)",
                    "$bom[0]=239","$bom[1]=187","$bom[2]=191",
                    "ONEC_GUID","one c" if False else "onec_guid",
                    "SOURCE_DB_WRITES=NO", "NETWORK_CALLS=NO",
                    "REVIEW_HELD=6", "PREVIOUS_EXPORT_DIAGNOSE_FIRST"):
            self.assertIn(tok,s)
        for bad in ("Read-Host","Invoke-WebRequest","curl.exe","ProtectedData",
                    "crm.item.add","crm.requisite.add","RegisterTaskDefinition",
                    "INSERT INTO customers", "UPDATE customers"):
            self.assertNotIn(bad,s)
if __name__=="__main__":
    unittest.main()

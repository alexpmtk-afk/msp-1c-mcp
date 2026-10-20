"""Contract for LocalService offline encrypted Bitrix webhook proof."""
from pathlib import Path
import unittest
SCRIPT=(Path(__file__).resolve().parents[1]/"bin"/"probe-bitrix-localservice-dpapi-offline.ps1")
class MachineDpapiProof(unittest.TestCase):
    def test_proof_is_offline_and_silent(self):
        s=SCRIPT.read_text("ascii")
        for key in (
            "#requires -version 2",
            "S-1-5-19",
            "bitrix-direct-private",
            "ProtectedData]::Unprotect",
            "DataProtectionScope]::LocalMachine",
            "ENROLLMENT_NOT_ACCEPTED",
            "bitrix-localservice-dpapi-status.txt",
            "DPAPI_UNPROTECT=PASS",
            "IDENTITY=LOCAL_SERVICE",
            "WEBHOOK_HOST=VALID",
            "SECRET_PRINTED=NO",
            "BITRIX_CALLS=0",
            "ONEC_CALLS=0",
            "PHASE=",
        ):
            self.assertIn(key,s)
        for key in ("Read-Host","Invoke-WebRequest","curl.exe","RegisterTaskDefinition","crm.item.add","crm.requisite.add","Write-Output $url","Write-Output $clear"):
            self.assertNotIn(key,s)
if __name__=="__main__":
    unittest.main()

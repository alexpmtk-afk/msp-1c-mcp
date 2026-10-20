"""Windows PowerShell 2 ACL constructor regression: keep inheritance flags separate."""
from pathlib import Path
import unittest

P=Path(__file__).resolve().parents[1]/"bin"/"enroll-bitrix-direct-webhook-v3.ps1"

class V3ACL(unittest.TestCase):
    def test_acl_uses_precomputed_inheritance(self):
        s=P.read_text("ascii")
        self.assertIn("$inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit",s)
        self.assertIn("($sid,$right,$inherit,[Security.AccessControl.PropagationFlags]::None",s)
        self.assertNotIn("ArgumentList @($sid,$right,[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor",s)
        self.assertIn("PRIVATE_DIRECTORY_ACL_CONSTRUCT",s)
        self.assertIn("EXCEPTION_TYPE=",s)
        self.assertIn("TEMP_PRIVATE_DIRECTORY_REMOVED=",s)
        self.assertIn("WEBHOOK_URL_PRINTED=NO",s)
        self.assertIn("ProtectedData]::Protect",s)
        self.assertIn("DataProtectionScope]::LocalMachine",s)
        self.assertNotIn("Invoke-WebRequest",s)
        self.assertNotIn("RegisterTaskDefinition",s)

if __name__=="__main__":
    unittest.main()

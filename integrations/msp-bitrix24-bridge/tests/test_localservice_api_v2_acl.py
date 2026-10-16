"""Strict ACL acceptance for LocalService V2: verify 4 exact rules and same enroller SID."""
from pathlib import Path
import unittest

B=Path(__file__).resolve().parents[1]/"bin"

class ServiceApiV2(unittest.TestCase):
    def test_v2_probe_acl_is_not_relaxed(self):
        s=(B/"probe-bitrix-localservice-api-readonly-v2.ps1").read_text("ascii")
        for marker in (
            "GetAccessRules", "AreAccessRulesProtected",
            "SECRET_ACL_RULE_COUNT_INVALID", "SECRET_ACL_RULE_TYPE_INVALID",
            "SECRET_ACL_DUPLICATE_SID", "SECRET_ACL_ENROLLER_ID_INVALID",
            "SECRET_ACL_RIGHTS_INVALID", "SECRET_ACL_PROPAGATION_INVALID",
            "SECRET_ACL_INHERITANCE_FLAGS_INVALID", "SECRET_ACL_FILE_FLAGS_INVALID",
            "SECRET_ACL_SERVICE_SID_MISSING", "SECRET_ACL_ENROLLER_MISMATCH",
            "S-1-5-18", "S-1-5-19", "S-1-5-32-544",
            "FileSystemRights]::Modify", "FileSystemRights]::ReadAndExecute",
            "FileSystemRights]::Read", "FileSystemRights]::FullControl",
            "bitrix-localservice-api-readonly-v2-status.txt",
            "LOCAL_SERVICE_REQUIRED", "ProtectedData]::Unprotect",
            "crm.requisite.preset.field.list.json",
            "WEBHOOK_SOURCE=MACHINE_DPAPI",
            "CRM_WRITES=NO", "ONEC_CALLS=NO",
        ): self.assertIn(marker,s)
        for forbidden in ("$currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value",
                          "Read-Host","Invoke-WebRequest","RegisterTaskDefinition",
                          "crm.item.add","crm.requisite.add","crm.requisite.update"):
            self.assertNotIn(forbidden,s)
        self.assertEqual(s.count("HttpOnce $url $payload"),1)

    def test_v2_parent_is_one_shot(self):
        s=(B/"run-bitrix-localservice-api-readonly-v2-once.ps1").read_text("ascii")
        for marker in (
            "MspBitrixLocalServiceApiV2Once", "OLD_FAILED_TASK_NOT_REMOVED",
            "PRIOR_FAILED_PROBE_RECEIPT_CHANGED",
            "bitrix-localservice-api-readonly-v2-status.txt",
            "PROBE_HASH_MISMATCH",
            "RegisterTaskDefinition","if($task.Definition.Triggers.Count -ne 0)",
            "DeleteTask($taskName,0)","TEMP_TASK_REMOVED=YES",
            "MAIN_AUTOSTART_CHANGED","NO_AUTOMATIC_RETRY=YES",
            "EXCEPTION_TYPE=",
            "CRM_WRITES=NO","ONEC_CALLS=NO",
        ): self.assertIn(marker,s)
        self.assertNotIn("Read-Host",s)
        self.assertNotIn("crm.item.add",s)
        self.assertEqual(s.count("$null=$task.Run($null)"),1)
        self.assertNotIn("__V2_CHILD_SHA256__",s)

if __name__=="__main__":
    unittest.main()

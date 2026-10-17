"""In-flight TEST buyer CRM read-only diagnostic safety gate."""
from pathlib import Path
import hashlib
import unittest
class InflightAudit(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script=(Path(__file__).resolve().parents[1]/"bin"/"audit-initial-buyer-inflight-v1.ps1").read_text("ascii")
    def test_no_customer_data_export_or_mutation(self):
        s=self.script
        for forbidden in (
            "crm.item.add?", "crm.item.update?", "crm.requisite.update?",
            "crm.item.delete?", "crm.requisite.add?", "crm.requisite.delete?",
            "WriteAllText($db", "BEGIN IMMEDIATE", "INSERT INTO ",
            "DELETE FROM ", "UPDATE msp_", "RegisterTaskDefinition",
            "Remove-Item", "msp_auto_tick", "127.0.0.1:8085"
        ):
            self.assertNotIn(forbidden,s)
        for token in ("#requires -version 2", "LOCAL_SERVICE_REQUIRED",
                      "V2_FAILURE_NOT_EXPECTED", "MAPPED=5;TARGET=6433",
                      "msp_initial_inflight", "SOURCE=TEST_NEWBASE",
                      "CRM_WRITES=0;DB_WRITES=0", "COMMENTS_EXACT=",
                      "COMMENTS_NULL=", "COMMENTS_DIFFERENT=",
                      "COMMENTS_CONTAIN_EXPECTED=", "IDENTITY_VERIFIED=",
                      "NOT_FOUND=", "AMBIGUOUS=", "NAME_EXACT="):
            self.assertIn(token,s)
    def test_validates_original_identity(self):
        s=self.script
        self.assertIn("filter[originatorId]=MSP_ONEC_NEWBASE",s)
        self.assertIn("filter[originId]=",s)
        self.assertIn("CRM_ORIGIN_MISMATCH",s)
        self.assertIn("crm.item.get?entityTypeId=",s)
        self.assertIn("VerifyBatchList $r $i '.items'",s)
        self.assertIn("function Field(",s)
        self.assertIn("json_extract(doc",s)
    def test_aggregate_no_guids_or_raw_names(self):
        s=self.script
        lines=[x for x in s.splitlines() if "WriteAllText($status" in x]
        self.assertEqual(2,len(lines))
        self.assertIn("STATUS=PASS",s)
        self.assertIn("STATUS=FAIL",s)
        self.assertNotIn("GUIDS=",s)
        print("INFLIGHT_AUDIT_SHA256="+hashlib.sha256((Path(__file__).resolve().parents[1]/"bin"/"audit-initial-buyer-inflight-v1.ps1").read_bytes()).hexdigest())
        self.assertNotIn("INNS=",s)
if __name__=="__main__": unittest.main()

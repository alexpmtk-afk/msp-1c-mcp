"""V4 initial buyer load validates origin ID while tracking stale fields."""
from pathlib import Path
import hashlib
import unittest
B=Path(__file__).resolve().parents[1]/"bin"
class BuyerV4(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.path=B/"import-all-newbase-buyers-once-v4.ps1"
  cls.script=cls.path.read_text("ascii")
 def test_identity_remains_mandatory(self):
  s=self.script
  for key in ("CRM_BACKREAD_ORIGIN_MISMATCH", "$rId -ne [string]$Ids[$i]",
              "$rOrigin -ne $Items[$i].guid", "$rOwner -ne 'MSP_ONEC_NEWBASE'",
              "CRM_VISIBLE_NAME_READ_INVALID","CRM_COMMENTS_READ_INVALID",
              "NAME_MISMATCH","NAME_AND_COMMENTS_MISMATCH","COMMENTS_MISMATCH",
              "function CommitMap($Items,$Ids,$Review)",
              "UNEXPECTED_REVIEW_STATE","PRIOR_CREATE_UNCERTAIN_MANUAL_RECONCILE",
              "msp_initial_inflight", "msp_initial_details_review",
              "MspOneTimeAllBuyersImportV4", "bitrix-initial-all-buyers-v4.status",
              "PASS_WITH_FIELD_REVIEW", "TOTAL_IN_CRM_ORIGIN_IDENTITY_VERIFIED=6433",
              "NAMES_REVIEW=", "FIELDS_REVIEW=", "6433:1941:4486:6",
              "SOURCE=TEST_NEWBASE", "AUTO_UPDATE=OFF",
              "NO_BLIND_RETRY=YES"):
   self.assertIn(key,s)
  self.assertNotIn("Fail 'CRM_VISIBLE_NAME_MISMATCH'",s)
  self.assertNotIn("Fail 'CRM_DETAILS_BACKREAD_MISMATCH'",s)
  self.assertNotIn(" -notin ",s)
  self.assertNotIn("crm.item.update?",s)
  self.assertNotIn("crm.item.delete?",s)
  self.assertLess(s.index("$existingReview=Verify $already"),s.index("CommitMap $already"))
  self.assertLess(s.index("$newReview=Verify $new"),s.index("CommitMap $new"))
 def test_review_is_local_durable_not_claimed_clean(self):
  s=self.script
  self.assertIn("INSERT INTO msp_initial_details_review",s)
  self.assertIn("NAME_AND_COMMENTS_MISMATCH",s)
  self.assertIn("STATUS='+$status",s)
  self.assertIn("WHERE detail_state IN ('NAME_MISMATCH','NAME_AND_COMMENTS_MISMATCH')",s)
  self.assertNotIn("TOTAL_IN_CRM_IDENTITY_AND_NAME_VERIFIED",s)
  self.assertNotIn("\r",s)
  print("BULK_V4_WORKER_SHA256="+hashlib.sha256(self.path.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

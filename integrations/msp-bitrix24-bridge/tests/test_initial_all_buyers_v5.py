"""V5 recovery must not blindly repeat Bitrix24 creation, only read operations."""
import hashlib
import unittest
from pathlib import Path
B=Path(__file__).resolve().parents[1]/"bin"
class V5(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.path=B/"import-all-newbase-buyers-once-v5.ps1"
  cls.s=cls.path.read_text("ascii")
 def test_source_and_review_are_preserved(self):
  s=self.s
  for marker in ("msp_initial_map","msp_initial_inflight","msp_initial_details_review",
                 "NAME_MISMATCH","COMMENTS_MISMATCH","NAME_AND_COMMENTS_MISMATCH",
                 "6433:1941:4486:6","bitrix-initial-all-buyers-v5.status",
                 "MspOneTimeAllBuyersImportV5","PASS_WITH_FIELD_REVIEW",
                 "RESULT=FAIL;STAGE=NEWBASE_ALL_BUYERS_INITIAL_CRM_IMPORT_V5",
                 "CREATE_RESULT_AMBIGUOUS_NO_RETRY",
                 "PRIOR_CREATE_UNCERTAIN_MANUAL_RECONCILE"):
   self.assertIn(marker,s)
  self.assertNotIn("bitrix-initial-all-buyers-v4.status",s)
 def test_readonly_retry_gate(self):
  s=self.s
  self.assertIn("function ReadOnlyBatch([object[]]$Commands)",s)
  self.assertIn("for($attempt=1;$attempt -le 3;$attempt++)",s)
  self.assertIn("READONLY_RETRY_METHOD_DENIED",s)
  self.assertIn("'NEWBASE_CURL_FAILED'",s)
  self.assertIn("'NEWBASE_HTTP_429'",s)
  self.assertIn("'NEWBASE_HTTP_503'",s)
  self.assertIn(" $answer=ReadOnlyBatch @($commands.ToArray())",s)
  self.assertIn(" $answer=ReadOnlyBatch @($q.ToArray())",s)
  self.assertIn("   $reply=Batch @($commands.ToArray())",s)
  self.assertEqual(2,s.count("ReadOnlyBatch @("))
  self.assertIn("   $phase='PERSIST_BEFORE_CREATE'",s)
  self.assertLess(s.index("PERSIST_BEFORE_CREATE"),s.index("$phase='CRM_CREATE_BATCH'"))
  self.assertNotIn(" -notin ",s)
 def test_pinned_hash(self):
  print("BULK_V5_WORKER_SHA256="+hashlib.sha256(self.path.read_bytes()).hexdigest())
if __name__=="__main__": unittest.main()

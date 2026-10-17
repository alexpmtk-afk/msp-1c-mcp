"""PII-free read-only one-shot LocalService inflight audit: operator gates."""
from pathlib import Path
import hashlib
import unittest
BIN=Path(__file__).resolve().parents[1]/"bin"
class AuditLauncher(unittest.TestCase):
    def test_guarded_manual_only(self):
        f=BIN/"start-initial-inflight-audit-v1.ps1"
        s=f.read_text("ascii")
        for text in ("#requires -version 2","STATUS=FAIL;GATE=CRM_DETAILS_BACKREAD_MISMATCH",
                     "MAPPED=5;TARGET=6433","msp_initial_map",
                     "msp_initial_inflight","MspNewBaseInitialImportV2",
                     "MspNewBaseInflightAuditV1","STAGING_ALREADY_EXISTS",
                     "AUDIT_TASK_ALREADY_PRESENT","READONLY_AUDIT_TASK=STARTED",
                     "UNEXPECTED_AUTO_TRIGGERS","bb96d148f261e7180706851bea1d21f29041dcd0128ff887afdd68e81257feb4",
                     "6d6d1c385c0dc648310772fce86be7936bb30cbafb3790c5ae48cc4fcbc8e852",
                     "CRM_WRITES=NO","SQLITE_WRITES=NO","ONEC_REQUESTS=NO"):
            self.assertIn(text,s)
        for bad in ("Triggers.Create","DeleteTask(", "crm.item.add?", "crm.item.update?", "msp-newbase-auto-tick-v2"):
            self.assertNotIn(bad,s)
        self.assertNotIn("\r",s)
        print("INFLIGHT_AUDIT_LAUNCHER_SHA256="+hashlib.sha256(f.read_bytes()).hexdigest())
if __name__=="__main__": unittest.main()

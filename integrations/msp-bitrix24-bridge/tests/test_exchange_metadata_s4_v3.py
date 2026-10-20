"""S4 V3 network diagnostic and safe offline XML regression, no SRV interactions."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
V2 = ROOT / "bin" / "survey-exchange-plan-metadata-service-v2.ps1"
V3 = ROOT / "bin" / "survey-exchange-plan-metadata-service-v3.ps1"

class S4V3(unittest.TestCase):
    def test_v3_only_metadata_get_and_bounded_error_info(self):
        s = V3.read_text(encoding="utf-8")
        for expected in (
            "#requires -version 2",
            "exchange-plan-metadata-s4-v3.txt",
            "S4_WEBEXCEPTION_STATUS=",
            "S4_REQUEST_ELAPSED_MS=",
            "$phase='ODATA_METADATA_GET'",
            "$phase='ODATA_METADATA_BODY'",
            "ODATA_'+$webStatus",
            "$req.Method='GET'",
            "$req.Timeout=30000",
            "SRV_ONEC_EXCHANGE_METADATA_SURVEY_V3",
            "OFFLINE_FIXTURE_CI_ONLY",
            "DtdProcessing",
            "S4_CHANGE_REGISTRATION_READY=NOT_PROVEN",
        ):
            self.assertIn(expected, s)
        for forbidden in (
            "$req.Method='POST'", "SelectChanges(", "NotifyChangesReceived(",
            "ConfirmChanges", "RegisterTaskDefinition", "Run($null)",
            "DeleteTask(", "Invoke-WebRequest", "MspOnecHttpsAgentSystem",
        ):
            self.assertNotIn(forbidden, s)
        self.assertNotIn("\r", s)

    def test_no_changes_in_pinned_v2(self):
        v2 = V2.read_text(encoding="utf-8")
        self.assertIn("exchange-plan-metadata-s4-v2.txt", v2)
        self.assertNotIn("S4_WEBEXCEPTION_STATUS=", v2)
        self.assertNotIn("ODATA_METADATA_BODY", v2)

if __name__ == "__main__":
    unittest.main()

"""S4 v2 read-only OData metadata parser: synthetic offline safety regression."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from xml.etree.ElementTree import Element, SubElement, tostring

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "survey-exchange-plan-metadata-service-v2.ps1"

def fixture(extra=0, operations=True, duplicate=False, dtd=False):
    edmx = Element("Edmx")
    schema = SubElement(edmx, "Schema")
    container = SubElement(schema, "EntityContainer")
    SubElement(container, "EntitySet", Name="Catalog_Контрагенты")
    SubElement(container, "EntitySet", Name="ExchangePlan_МСПБитрикс")
    if duplicate:
        SubElement(container, "EntitySet", Name="ExchangePlan_МСПБитрикс")
    for i in range(extra):
        SubElement(container, "EntitySet", Name="Catalog_Item%04d" % i)
    if operations:
        SubElement(container, "FunctionImport", Name="SelectChanges")
        SubElement(container, "FunctionImport", Name="NotifyChangesReceived")
    xml = tostring(edmx, encoding="unicode")
    if dtd:
        xml = '<!DOCTYPE x [<!ENTITY leak "abc">]>' + xml
    return xml

class SurveyV2Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SCRIPT.read_text(encoding="utf-8")
        cls.shell = shutil.which("powershell.exe") or shutil.which("powershell")

    def test_isolated_and_readonly_by_contract(self):
        s = self.source
        self.assertTrue(s.startswith("#requires -version 2"))
        for needed in (
            "OfflineFixturePath", "S4_NO_NETWORK=YES", "S4_NO_WRITES=YES",
            "NotifyChangesReceived", "DtdProcessing", "OFFLINE_FIXTURE_CI_ONLY",
            "exchange-plan-metadata-s4-v2.txt", "S4_EXCEPTION_TYPE=",
            "$req.Method='GET'", "S4_CHANGE_REGISTRATION_READY=NOT_PROVEN"
        ):
            self.assertIn(needed, s)
        for forbidden in (
            "$req.Method='POST'", "ConfirmChanges", "RegisterTaskDefinition",
            "Run($null)", "DeleteTask(", "MspOnecHttpsAgentSystem"
        ):
            self.assertNotIn(forbidden, s)
        self.assertLess(s.index("if($OfflineFixturePath -ne '')"), s.index("if($env:COMPUTERNAME -ne"))
        self.assertNotIn("\r", s)

    def run_fixture(self, xml):
        if not self.shell:
            self.skipTest("Windows PowerShell is available on Windows CI")
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "synthetic.xml"
            path.write_text(xml, encoding="utf-8")
            env = os.environ.copy()
            env["CI"] = "true"
            return subprocess.run(
                [self.shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                 "-File", str(SCRIPT), "-OfflineFixturePath", str(path)],
                capture_output=True, text=True, timeout=30, env=env,
            )

    def test_valid_metadata_one_plan(self):
        r = self.run_fixture(fixture())
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        for result in (
            "S4_ENTITY_SET_COUNT=2", "S4_EXCHANGE_PLAN_SET_COUNT=1",
            "S4_SELECTCHANGES_DECLARED=True",
            "S4_NOTIFYCHANGESRECEIVED_DECLARED=True",
            "S4_NO_NETWORK=YES", "S4_NO_WRITES=YES",
            "RESULT=PASS;STAGE=SRV_ONEC_EXCHANGE_METADATA_SURVEY_V2_OFFLINE"
        ):
            self.assertIn(result, r.stdout)

    def test_large_realistic_metadata(self):
        r = self.run_fixture(fixture(extra=1490, operations=False))
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("S4_ENTITY_SET_COUNT=1492", r.stdout)
        self.assertIn("S4_EXCHANGE_PLAN_SET_COUNT=1", r.stdout)
        self.assertIn("S4_NOTIFYCHANGESRECEIVED_DECLARED=False", r.stdout)

    def test_duplicate_exchange_plan_rejected(self):
        r = self.run_fixture(fixture(duplicate=True))
        self.assertNotEqual(0, r.returncode)
        self.assertIn("GATE=EXCHANGE_PLAN_DUPLICATE", r.stdout)

    def test_malformed_xml_fail_closed_without_payload(self):
        r = self.run_fixture("<broken>")
        self.assertNotEqual(0, r.returncode)
        self.assertIn("S4_EXCEPTION_TYPE=XmlException", r.stdout)
        self.assertNotIn("<broken>", r.stdout)

    def test_doctype_prohibited(self):
        r = self.run_fixture(fixture(dtd=True))
        self.assertNotEqual(0, r.returncode)
        self.assertIn("S4_EXCEPTION_TYPE=XmlException", r.stdout)

if __name__ == "__main__":
    unittest.main()

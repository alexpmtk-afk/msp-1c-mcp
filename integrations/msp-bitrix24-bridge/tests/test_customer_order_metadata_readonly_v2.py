"""V2 recovery of real UNF customer-order metadata with >20 table parts."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

from test_customer_order_metadata_readonly_v1 import metadata, NAME

ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / "bin" / "probe-newbase-customer-orders-metadata-readonly-v2.ps1"
STARTER = ROOT / "bin" / "start-newbase-customer-orders-metadata-readonly-v2.ps1"
EDM = "{http://schemas.microsoft.com/ado/2008/09/edm}"


def many_parts(amount=27):
    xml = ET.fromstring(metadata(with_part=False))
    schema = xml.find(".//" + EDM + "Schema")
    container = schema.find(EDM + "EntityContainer")
    for n in range(amount):
        name = NAME + "_Дополнение" + str(n)
        target = n == amount - 1
        if target:
            name = NAME + "_Товары"
        ET.SubElement(container, EDM + "EntitySet", Name=name, EntityType="Test." + name)
        t = ET.SubElement(schema, EDM + "EntityType", Name=name)
        ET.SubElement(t, EDM + "Property", Name="LineNumber", Type="Edm.Int32")
        ET.SubElement(t, EDM + "Property", Name="Ref_Key", Type="Edm.Guid")
        if target:
            for key, typ in (("Номенклатура_Key", "Edm.Guid"),
                             ("Количество", "Edm.Decimal"), ("Цена", "Edm.Decimal")):
                ET.SubElement(t, EDM + "Property", Name=key, Type=typ)
    return ET.tostring(xml, encoding="unicode", xml_declaration=True)


class CustomerOrderMetadataV2(unittest.TestCase):
    def test_safety_and_retry_contract(self):
        worker = WORKER.read_text(encoding="utf-8")
        launcher = STARTER.read_text(encoding="utf-8")
        self.assertTrue(worker.startswith("#requires -version 2"))
        self.assertTrue(launcher.startswith("#requires -version 2"))
        for key in ("PART_NAME=", "DETAILED_PRODUCT_PARTS=", "PART_COUNT_UNEXPECTED",
                    "PART_FIELD_OVERFLOW", "TOO_MANY_PRODUCT_PARTS", "RELATED_PART_SETS=",
                    "bitrix-to-onec-customer-order-metadata-v2.txt", "GET_ONLY=YES",
                    "ONEC_WRITES=0;CRM_REQUESTS=0;SQLITE_WRITES=0", "MCP_OData_ReadOnly"):
            self.assertIn(key, worker)
        for key in ("V1_PARSE_ONLY_FAILURE=VERIFIED", "V1_FAILURE_MISMATCH",
                    "MspOnecCustomerOrderMetadataReadOnlyV1", "MspOnecCustomerOrderMetadataReadOnlyV2",
                    "V1_TASK_NOT_FAILED_IDLE", "Triggers.Count -eq 0",
                    "4dbb996124f2ce1059f3b6cac698c37a03e8ec5f",
                    "901e93f62c38d80882242c86e8c0bb8023502862"):
            self.assertIn(key, launcher)
        for forbidden in ("$req.Method='POST'", "crm.item.update", "DELETE FROM",
                          "CREATE TABLE", "DeleteTask(", "/Post", "ONEC_WRITES=YES"):
            self.assertNotIn(forbidden, worker + launcher)

    @unittest.skipUnless(sys.platform == "win32", "Windows PowerShell only")
    def test_27_parts_including_late_product_part(self):
        output, code = self.run_fixture(many_parts())
        self.assertEqual(code, 0, output)
        self.assertIn("RELATED_PART_SETS=27", output)
        self.assertIn("DETAILED_PRODUCT_PARTS=1", output)
        self.assertEqual(output.count("PART_NAME="), 27)
        self.assertEqual(output.count("PART_SET="), 1)
        self.assertIn("PART_FIELDS=5", output)
        self.assertIn("RESULT=PASS;STAGE=ONEC_CUSTOMER_ORDER_METADATA_READONLY_V2", output)

    @unittest.skipUnless(sys.platform == "win32", "Windows PowerShell only")
    def test_above_250_parts_fails_closed(self):
        output, code = self.run_fixture(many_parts(251))
        self.assertNotEqual(code, 0, output)
        self.assertIn("GATE=PART_COUNT_UNEXPECTED", output)

    @unittest.skipUnless(sys.platform == "win32", "Windows PowerShell only")
    def test_no_order_is_safely_reported(self):
        output, code = self.run_fixture(metadata(with_document=False))
        self.assertEqual(code, 0, output)
        self.assertIn("ROOT_ORDER_CANDIDATES=0", output)

    def run_fixture(self, source):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "synthetic.xml"
            path.write_text(source, encoding="utf-8")
            env = os.environ.copy()
            env["CI"] = "true"
            task = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive",
                                   "-ExecutionPolicy", "Bypass", "-File", str(WORKER),
                                   "-OfflineFixturePath", str(path)],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  env=env, timeout=60)
            return (task.stdout.decode("utf-8", errors="replace")
                    + "\n" + task.stderr.decode("utf-8", errors="replace")), task.returncode


if __name__ == "__main__":
    unittest.main()

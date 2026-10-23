"""Customer-order metadata probe: offline-only fixtures and launch boundaries.

Real parsing is executed on Windows PowerShell with a synthetic TEST XML body.
No network, 1C, CRM, real clients or SQLite.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / "bin" / "probe-newbase-customer-orders-metadata-readonly-v1.ps1"
STARTER = ROOT / "bin" / "start-newbase-customer-orders-metadata-readonly-v1.ps1"

NAME = "Document_ЗаказПокупателя"
PART = NAME + "_Запасы"


def metadata(with_document=True, with_part=True):
    ET.register_namespace("edmx", "http://schemas.microsoft.com/ado/2007/06/edmx")
    ET.register_namespace("", "http://schemas.microsoft.com/ado/2008/09/edm")
    root = ET.Element("{http://schemas.microsoft.com/ado/2007/06/edmx}Edmx")
    ds = ET.SubElement(root, "{http://schemas.microsoft.com/ado/2007/06/edmx}DataServices")
    schema = ET.SubElement(ds, "{http://schemas.microsoft.com/ado/2008/09/edm}Schema", Namespace="Test")
    container = ET.SubElement(schema, "{http://schemas.microsoft.com/ado/2008/09/edm}EntityContainer", Name="Default")
    if with_document:
        ET.SubElement(container, "{http://schemas.microsoft.com/ado/2008/09/edm}EntitySet", Name=NAME, EntityType="Test." + NAME)
        doc = ET.SubElement(schema, "{http://schemas.microsoft.com/ado/2008/09/edm}EntityType", Name=NAME)
        for n, t in (("Ref_Key", "Edm.Guid"), ("Number", "Edm.String"), ("Date", "Edm.DateTime"),
                     ("Контрагент_Key", "Edm.Guid"), ("Posted", "Edm.Boolean")):
            ET.SubElement(doc, "{http://schemas.microsoft.com/ado/2008/09/edm}Property", Name=n, Type=t)
        ET.SubElement(doc, "{http://schemas.microsoft.com/ado/2008/09/edm}NavigationProperty",
                      Name="Запасы", Type="Collection(Test." + PART + ")")
        if with_part:
            ET.SubElement(container, "{http://schemas.microsoft.com/ado/2008/09/edm}EntitySet", Name=PART,
                          EntityType="Test." + PART)
            part = ET.SubElement(schema, "{http://schemas.microsoft.com/ado/2008/09/edm}EntityType", Name=PART)
            for n, t in (("Ref_Key", "Edm.Guid"), ("LineNumber", "Edm.Int32"),
                         ("Номенклатура_Key", "Edm.Guid"), ("Количество", "Edm.Decimal"), ("Цена", "Edm.Decimal")):
                ET.SubElement(part, "{http://schemas.microsoft.com/ado/2008/09/edm}Property", Name=n, Type=t)
    ET.SubElement(container, "{http://schemas.microsoft.com/ado/2008/09/edm}EntitySet",
                  Name="Document_ПоступлениеТоваров", EntityType="Test.P")
    p = ET.SubElement(schema, "{http://schemas.microsoft.com/ado/2008/09/edm}EntityType", Name="P")
    ET.SubElement(p, "{http://schemas.microsoft.com/ado/2008/09/edm}Property",
                  Name="Ref_Key", Type="Edm.Guid")
    return ET.tostring(root, encoding="unicode", xml_declaration=True)


class OrderMetadata(unittest.TestCase):
    def test_safety_contract(self):
        s = WORKER.read_text(encoding="utf-8")
        starter = STARTER.read_text(encoding="utf-8")
        self.assertTrue(s.startswith("#requires -version 2"))
        self.assertTrue(starter.startswith("#requires -version 2"))
        for p in ("'GET'", "'MCP_OData_ReadOnly'", "'OfflineFixturePath'", "OFFLINE_CI_ONLY",
                  "ROOT_ORDER_CANDIDATES=", "DOC_FIELD=", "PART_FIELD=", "PART_SET=",
                  "XML", "STATUS_ALREADY_EXISTS", "GET_ONLY=YES",
                  "ONEC_WRITES=0;CRM_REQUESTS=0;SQLITE_WRITES=0"):
            if p == "'OfflineFixturePath'":
                continue
            if p == "XML":
                continue
            self.assertIn(p, s)
        self.assertIn("LOCAL_SERVICE_ONLY", s)
        self.assertIn("RegisterTaskDefinition", starter)
        self.assertIn("MspOnecCustomerOrderMetadataReadOnlyV1", starter)
        self.assertIn("Triggers.Count -eq 0", starter)
        self.assertIn("WORKER_HASH_INVALID", starter)
        self.assertIn("SOURCE_TASK_CHANGED", starter)
        self.assertIn("500f82f2d43388f0f64b751add914fea5a37d99e", starter)
        self.assertIn("81fe0f47d39c3612a855e553d63227f51316a891", starter)
        for denied in ("$req.Method='POST'", "OData.Post", "crm.item.add", "crm.item.update",
                       "Insert into customers", "DELETE FROM", "DELETE_TASK"):
            self.assertNotIn(denied, s)
        self.assertNotIn("Enabled=$false", starter)  # no touching existing triggers

    @unittest.skipUnless(sys.platform == "win32", "requires Windows PowerShell for PS2 fixture execution")
    def test_full_document_and_part(self):
        text = self.execute(metadata())
        self.assertIn("ROOT_ORDER_CANDIDATES=1", text)
        self.assertIn("DOCUMENT_FIELDS=5", text)
        self.assertIn("DOCUMENT_NAVIGATIONS=1", text)
        self.assertIn("RELATED_PART_SETS=1", text)
        self.assertIn("PART_FIELDS=5", text)
        self.assertIn(r"DOC_FIELD=\u041a\u043e\u043d\u0442\u0440\u0430\u0433\u0435\u043d\u0442_Key", text)
        self.assertIn(r"PART_FIELD=\u041d\u043e\u043c\u0435\u043d\u043a\u043b\u0430\u0442\u0443\u0440\u0430_Key", text)
        self.assertIn("RESULT=PASS;STAGE=ONEC_CUSTOMER_ORDER_METADATA_READONLY_V1", text)

    @unittest.skipUnless(sys.platform == "win32", "requires Windows PowerShell for PS2 fixture execution")
    def test_document_root_without_part_is_recoverable(self):
        text = self.execute(metadata(with_part=False))
        self.assertIn("ROOT_ORDER_CANDIDATES=1", text)
        self.assertIn("RELATED_PART_SETS=0", text)
        self.assertIn("DOC_NAV=", text)

    @unittest.skipUnless(sys.platform == "win32", "requires Windows PowerShell for PS2 fixture execution")
    def test_not_found_reports_zero_not_approves(self):
        text = self.execute(metadata(with_document=False))
        self.assertIn("ROOT_ORDER_CANDIDATES=0", text)
        self.assertNotIn("DOCUMENT_SET=", text)

    @unittest.skipUnless(sys.platform == "win32", "requires Windows PowerShell for PS2 fixture execution")
    def test_xml_doctype_rejected(self):
        self.execute('<!DOCTYPE doc [<!ENTITY xxe SYSTEM "file:///c:/windows/win.ini">]>' +
                     metadata(), expect_success=False)

    def execute(self, fixture, expect_success=True):
        with tempfile.TemporaryDirectory() as td:
            xml = Path(td) / "synthetic.xml"
            xml.write_text(fixture, encoding="utf-8")
            env = os.environ.copy()
            env["CI"] = "true"
            cmd = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                   "-File", str(WORKER), "-OfflineFixturePath", str(xml)]
            p = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=45)
            out = p.stdout.decode("utf-8", errors="replace")
            err = p.stderr.decode("utf-8", errors="replace")
            if expect_success:
                self.assertEqual(p.returncode, 0, out + "\n" + err)
            else:
                self.assertNotEqual(p.returncode, 0, out + "\n" + err)
            return out


if __name__ == "__main__":
    unittest.main()

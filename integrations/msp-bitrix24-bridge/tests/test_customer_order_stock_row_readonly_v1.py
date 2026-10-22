"""Offline Windows PowerShell tests for TEST NewBase one-row OData inspection."""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
from xml.sax.saxutils import escape

ROOT=Path(__file__).resolve().parents[1]
WORKER=ROOT/"bin"/"probe-newbase-order-stock-row-readonly-v1.ps1"
LAUNCHER=ROOT/"bin"/"start-newbase-order-stock-row-readonly-v1.ps1"

def atom_feed(row=True):
    if not row:
        return '<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"></feed>'
    vals={
      "Ref_Key":"12345678-1234-1234-1234-123456789abc",
      "LineNumber":"1", "Номенклатура":"ed0d1111-aaaa-bbbb-cccc-888877776666",
      "Номенклатура_Type":"StandardODATA.Catalog_Номенклатура",
      "Количество":"3.5", "Цена":"1050.15",
      "Характеристика_Key":"00000000-0000-0000-0000-000000000000",
      "СтавкаНДС_Key":"00000000-0000-0000-0000-000000000000",
      "ЕдиницаИзмерения":"шт", "ЕдиницаИзмерения_Type":"StandardODATA.Catalog_ЕдиницыИзмерения"
    }
    fields="\n".join(f"<d:{name}>{escape(value)}</d:{name}>" for name,value in vals.items())
    return f'''<?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata"
          xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices">
       <entry><content type="application/xml"><m:properties>{fields}</m:properties></content></entry>
    </feed>'''

class StockRowReadOnly(unittest.TestCase):
    def test_static_guards(self):
        w=WORKER.read_text("utf-8")
        l=LAUNCHER.read_text("utf-8")
        self.assertTrue(w.startswith("#requires -version 2"))
        self.assertTrue(l.startswith("#requires -version 2"))
        for string in ("ALREADY_RUN","TEST_NEWBASE","GET'","MCP_OData_ReadOnly",
                       "OFFLINE_CI_ONLY","RAW_DATA_EXPORTED=0",
                       "NOMENCLATURE_CLASS=","NOMENCLATURE_TYPE_CLASS=",
                       "ONEC_WRITES=0;CRM_WRITES=0","STATUS=FAIL","ONEC_STOCK_ROW_READONLY_V1"):
            self.assertIn(string,w)
        for string in ("V2_METADATA_NOT_ACCEPTED","V2_TASK_NOT_ACCEPTED",
                       "MspOnecCustomerOrderMetadataReadOnlyV2",
                       "MspOnecOrderStockRowReadOnlyV1",
                       "Triggers.Count -eq 0","WORKER_HASH_INVALID",
                       "fccaf132456b55812d2b1acce601a96fe8f9d832",
                       "3912d388445fb69fff3e8f0a129d10498d43cca6"):
            self.assertIn(string,l)
        for denied in ("$req.Method='POST'","$req.Method='PATCH'","RegisterTaskDefinition(",
                       "CREATE TABLE", "DELETE FROM","UPDATE customers",
                       "crm.item.update", "Drop table"):
            self.assertNotIn(denied,w)
        self.assertNotIn("DeleteTask(",l)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_one_row(self):
        out,code=self.execute(atom_feed())
        self.assertEqual(code,0,out)
        self.assertIn("ATOM_ENTRIES=1",out)
        self.assertIn("ROW_FOUND=YES",out)
        self.assertIn("NOMENCLATURE_CLASS=GUID_TEXT",out)
        self.assertIn("NOMENCLATURE_TYPE_PRESENT=YES",out)
        self.assertIn("QTY_CLASS=POSITIVE",out)
        self.assertIn("PRICE_CLASS=POSITIVE",out)
        self.assertIn("RESULT=PASS;STAGE=ONEC_STOCK_ROW_READONLY_V1",out)
        self.assertNotIn("1050.15",out)
        self.assertNotIn("ed0d1111",out)
        self.assertNotIn("12345678",out)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_zero_rows(self):
        out,code=self.execute(atom_feed(row=False))
        self.assertEqual(code,0,out)
        self.assertIn("ROW_FOUND=NO",out)
        self.assertIn("RESULT=PARTIAL",out)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_rejects_dtd(self):
        out,code=self.execute('<!DOCTYPE foo [<!ENTITY secret SYSTEM "file:///C:/windows/win.ini">]>'+atom_feed())
        self.assertNotEqual(code,0,out)
        self.assertIn("RESULT=FAIL",out)

    def execute(self,fixture):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/"test.xml"
            p.write_text(fixture,encoding="utf-8")
            env=dict(os.environ)
            env["CI"]="true"
            c=subprocess.run(["powershell.exe","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
                              "-File",str(WORKER),"-OfflineFixturePath",str(p)],
                             stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=45,env=env)
            return (c.stdout+c.stderr).decode("utf-8",errors="replace"),c.returncode

if __name__=="__main__":
    unittest.main()

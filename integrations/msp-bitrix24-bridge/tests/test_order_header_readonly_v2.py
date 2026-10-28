"""NewBase single customer-order header: offline PowerShell tests, redacted result."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from xml.sax.saxutils import escape

ROOT=Path(__file__).resolve().parents[1]
WORKER=ROOT/"bin"/"probe-newbase-order-header-readonly-v2.ps1"
LAUNCHER=ROOT/"bin"/"start-newbase-order-header-readonly-v2.ps1"

def fixture(with_order=True):
    if not with_order:
        return '<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom" />'
    fields={
        "Ref_Key":"12345678-1234-1234-1234-123456789abc",
        "Number":"TEST/123456",
        "Date":"2026-10-22T12:00:00",
        "Posted":"false",
        "DeletionMark":"false",
        "Контрагент_Key":"bbbbb111-1111-1111-1111-111111111111",
        "Организация_Key":"ccccc222-2222-2222-2222-222222222222",
        "Договор_Key":"00000000-0000-0000-0000-000000000000",
        "ВалютаДокумента_Key":"ddddd333-3333-3333-3333-333333333333",
        "ВидЦен_Key":"00000000-0000-0000-0000-000000000000",
        "ВидЗаказа":"Enum_ВидыЗаказов.Обычный",
        "ВидОперации":"Enum_ВидыОпераций.Продажа",
        "СостояниеЗаказа":"Enum_СостоянияЗаказов.Новый",
        "НалогообложениеНДС":"Enum_НалогообложениеНДС.Включено",
        "СуммаВключаетНДС":"true",
        "НДСВключатьВСтоимость":"false",
        "СуммаДокумента":"1650.75",
    }
    items="\n".join(f"<d:{k}>{escape(v)}</d:{k}>" for k,v in fields.items())
    return f'''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices"
 xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata"><entry>
<content type="application/xml"><m:properties>{items}</m:properties></content></entry></feed>'''

class HeaderProbe(unittest.TestCase):
    def test_safety_contract(self):
        w=WORKER.read_text("ascii");l=LAUNCHER.read_text("ascii")
        self.assertTrue(w.startswith("#requires -version 2"))
        self.assertTrue(l.startswith("#requires -version 2"))
        for token in ("ORDER_GUID_STATE=","ORDER_NUMBER_PRESENT=","BUYER_GUID_STATE=",
                      "ORGANIZATION_GUID_STATE=","CONTRACT_GUID_STATE=","POSTED_FLAG=",
                      "VAT_INCLUDED_FLAG=","TOTAL_CLASS=","RAW_DATA_EXPORTED=0",
                      "ONEC_WRITES=0;CRM_WRITES=0", "LOCAL_SERVICE_ONLY", "OFFLINE_CI_ONLY"):
            self.assertIn(token,w)
        for token in ("HEADER_V1_RECEIPT_NOT_ACCEPTED","HEADER_V1_TASK_NOT_ACCEPTED","ROW_V2_RECEIPT_NOT_ACCEPTED","ROW_V2_TASK_NOT_ACCEPTED",
                      "MspOnecOrderHeaderReadOnlyV2","c5030e1e145863e7541d690c7f26f4f9f1046939",
                      "c7fe77c3df1ba521d4d594a91b4c7e688991ff2e",
                      "Triggers.Count -eq 0","WORKER_HASH_INVALID"):
            self.assertIn(token,l)
        for token in ("$filter=DeletionMark%20eq%20false","MARKED_FOR_DELETION","LOCAL_SERVICE_ONLY"):
            self.assertIn(token,w)
        for token in ("$req.Method='POST'","$req.Method='PATCH'","crm.item.update",
                      "DELETE FROM","CREATE TABLE","RegisterTaskDefinition("):
            self.assertNotIn(token,w)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_existing_order_redacted(self):
        out,code=self.run_fixture(fixture())
        self.assertEqual(code,0,out)
        self.assertIn("ROW_FOUND=YES",out)
        self.assertIn("ORDER_NUMBER_PRESENT=NONEMPTY",out)
        self.assertIn("BUYER_GUID_STATE=NONZERO_GUID",out)
        self.assertIn("CONTRACT_GUID_STATE=ZERO_GUID",out)
        self.assertIn("POSTED_FLAG=FALSE",out)
        self.assertIn("ORDER_KIND_SHAPE=ENUM",out)
        self.assertIn("DELETION_FLAG=FALSE",out)
        self.assertIn("TOTAL_CLASS=POSITIVE",out)
        self.assertIn("RESULT=PASS;STAGE=ONEC_ORDER_HEADER_READONLY_V2",out)
        for secret in ("TEST/123456","1650.75","12345678","bbbbb111","2026-10-22T12:00:00"):
            self.assertNotIn(secret,out)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_deleted_order_rejected(self):
        bad=fixture().replace("<d:DeletionMark>false</d:DeletionMark>","<d:DeletionMark>true</d:DeletionMark>")
        out,code=self.run_fixture(bad)
        self.assertNotEqual(code,0,out)
        self.assertIn("GATE=MARKED_FOR_DELETION",out)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_no_order(self):
        out,code=self.run_fixture(fixture(False))
        self.assertEqual(code,0,out)
        self.assertIn("ROW_FOUND=NO",out)
        self.assertIn("RESULT=PARTIAL",out)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_dtd_denied(self):
        out,code=self.run_fixture('<!DOCTYPE a [<!ENTITY xxe SYSTEM "file:///c:/windows/win.ini">]>'+fixture())
        self.assertNotEqual(code,0,out)
        self.assertIn("RESULT=FAIL",out)

    def run_fixture(self,body):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"fixture.xml";p.write_text(body,encoding="utf-8")
            env=dict(os.environ,CI="true")
            p=subprocess.run(["powershell.exe","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
                              "-File",str(WORKER),"-OfflineFixturePath",str(p)],
                             stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=45,env=env)
            return (p.stdout+p.stderr).decode("utf-8",errors="replace"),p.returncode

if __name__=="__main__":
    unittest.main()

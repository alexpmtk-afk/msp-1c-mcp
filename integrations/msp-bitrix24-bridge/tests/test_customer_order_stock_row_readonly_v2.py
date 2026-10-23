"""Offline-only acceptance: Unicode composite-type classification, zero GUID safeguards.

No real 1C/CRM/SQLite access, no names, IDs or monetary amounts printed by worker.
"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from test_customer_order_stock_row_readonly_v1 import atom_feed

ROOT=Path(__file__).resolve().parents[1]
WORKER=ROOT/"bin"/"probe-newbase-order-stock-row-readonly-v2.ps1"
LAUNCHER=ROOT/"bin"/"start-newbase-order-stock-row-readonly-v2.ps1"

class CustomerOrderStockV2(unittest.TestCase):
    def test_safety_static(self):
        w=WORKER.read_text(encoding="ascii")
        l=LAUNCHER.read_text(encoding="ascii")
        self.assertTrue(w.startswith("#requires -version 2"))
        self.assertTrue(l.startswith("#requires -version 2"))
        self.assertIn("NOMENCLATURE_TYPE_EXPECTED=",w)
        self.assertIn("NOMENCLATURE_TYPE_FAMILY=",w)
        self.assertIn("UNIT_TYPE_FAMILY=",w)
        self.assertIn("CHARACTERISTIC_GUID_STATE=",w)
        self.assertIn("VAT_RATE_GUID_STATE=",w)
        self.assertIn("RAW_DATA_EXPORTED=0",w)
        self.assertIn("bitrix-to-onec-stock-row-readonly-v2.txt",w)
        self.assertIn("LOCAL_SERVICE_ONLY",w)
        self.assertIn("V1_ROW_RECEIPT=VERIFIED",l)
        self.assertIn("V1_ROW_TASK_NOT_ACCEPTED",l)
        self.assertIn("V1_RECEIPT_NOT_ACCEPTED",l)
        self.assertIn("MspOnecOrderStockRowReadOnlyV2",l)
        self.assertIn("34881b9cff7d698f34e06062e3bae74782ece9e5",l)
        self.assertIn("a70a812a2d283a7e74a710a9c3065da73b931a2c",l)
        self.assertNotIn("DeleteTask(",l)
        for banned in ("$req.Method='POST'", "$req.Method='PATCH'", "DELETE FROM","CREATE TABLE","crm.item.update"):
            self.assertNotIn(banned,w)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_unicode_technical_identifiers_and_zero_guid(self):
        out,code=self.execute(atom_feed())
        self.assertEqual(code,0,out)
        self.assertIn("ROW_FOUND=YES",out)
        self.assertIn("NOMENCLATURE_TYPE_FAMILY=CATALOG",out)
        self.assertIn("NOMENCLATURE_TYPE_EXPECTED=YES",out)
        self.assertIn("UNIT_TYPE_FAMILY=CATALOG",out)
        self.assertIn("CHARACTERISTIC_GUID_STATE=ZERO_GUID",out)
        self.assertIn("VAT_RATE_GUID_STATE=ZERO_GUID",out)
        self.assertIn("RESULT=PASS;STAGE=ONEC_STOCK_ROW_READONLY_V2",out)
        self.assertNotIn("ed0d1111",out)
        self.assertNotIn("1050.15",out)
        self.assertNotIn("StandardODATA.Catalog_",out)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_empty_feed_is_nonwrite_partial(self):
        out,code=self.execute(atom_feed(row=False))
        self.assertEqual(code,0,out)
        self.assertIn("ROW_FOUND=NO",out)
        self.assertIn("RESULT=PARTIAL;STAGE=ONEC_STOCK_ROW_READONLY_V2",out)

    @unittest.skipUnless(sys.platform=="win32","Windows PowerShell only")
    def test_rejects_malicious_dtd(self):
        out,code=self.execute('<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///C:/Windows/win.ini">]>'+atom_feed())
        self.assertNotEqual(code,0,out)
        self.assertIn("RESULT=FAIL",out)

    def execute(self,fixture):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"test.xml"
            p.write_text(fixture,encoding="utf-8")
            env=dict(os.environ,CI="true")
            r=subprocess.run(["powershell.exe","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
                              "-File",str(WORKER),"-OfflineFixturePath",str(p)],stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE,env=env,timeout=40)
            return (r.stdout+r.stderr).decode("utf-8",errors="replace"),r.returncode

if __name__=="__main__":
    unittest.main()

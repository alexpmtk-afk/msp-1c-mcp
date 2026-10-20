"""Check one-shot Bitrix24 preset field probe is a read-only PS2 contract."""
from pathlib import Path
import sqlite3
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"

class PresetFieldSafety(unittest.TestCase):
    def test_read_only_fields_preset_one(self):
        s=(BIN/"probe-bitrix-company-preset-fields-readonly.ps1").read_text("ascii")
        for term in ("#requires -version 2",
                     "crm.requisite.preset.field.list.json",
                     '"preset":{"ID":1}', "RQ_INN", "RQ_KPP", "RQ_OGRN",
                     "RQ_COMPANY_NAME", "RQ_COMPANY_FULL_NAME",
                     "FIELDS_PARTIAL_PAGE", "PAGING_PRESENT",
                     "bitrix-direct-requisite-preset-details-status.txt",
                     "bitrix-direct-company-preset-fields-readonly-status.txt",
                     "DIRECT_BITRIX_COMPANY_PRESET_FIELDS=PASS",
                     "CRM_WRITES=NO", "ONEC_CALLS=NO",
                     "CUSTOMER_DATA_EXPORTED=NO", "WEBHOOK_SOURCE=MACHINE_DPAPI",
                     "WEBHOOK_SAVED=YES_ENCRYPTED", "WEBHOOK_NOT_ENROLLED"):
            self.assertIn(term,s)
        for term in ("crm.item.add", "crm.item.update", "crm.item.delete",
                     "crm.requisite.add", "crm.requisite.update",
                     "Invoke-WebRequest","ConvertFrom-Json", "RegisterTaskDefinition("):
            self.assertNotIn(term,s)
        self.assertNotIn('Read-Host',s)

    def test_json1_field_name_counts(self):
        con=sqlite3.connect(":memory:")
        value='{"result":[{"ID":1,"FIELD_NAME":"RQ_INN"},{"ID":2,"FIELD_NAME":"RQ_KPP"},{"ID":3,"FIELD_NAME":"RQ_COMPANY_NAME"}]}'
        query="""WITH j(doc) AS (SELECT ?)
          SELECT 'OK|'||
          sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_INN' THEN 1 ELSE 0 END)||'|'||
          sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_KPP' THEN 1 ELSE 0 END)||'|'||
          sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_OGRN' THEN 1 ELSE 0 END)||'|'||
          sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_COMPANY_NAME' THEN 1 ELSE 0 END)||'|'||
          sum(CASE WHEN json_extract(e.value,'$.FIELD_NAME')='RQ_COMPANY_FULL_NAME' THEN 1 ELSE 0 END)
          FROM j,json_each(j.doc,'$.result') AS e;"""
        self.assertEqual(con.execute(query,(value,)).fetchone()[0], "OK|1|1|0|1|0")
        con.close()

if __name__=="__main__":
    unittest.main()

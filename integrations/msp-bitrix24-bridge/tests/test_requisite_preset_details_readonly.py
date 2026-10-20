"""Read-only requisite preset detail output contract."""
from pathlib import Path
import sqlite3
import unittest

ROOT=Path(__file__).resolve().parents[1]/"bin"

class PresetDetailsContract(unittest.TestCase):
    def test_one_shot_metadata_only(self):
        code=(ROOT/"list-bitrix-direct-requisite-preset-details.ps1").read_text("ascii")
        for term in (
            "#requires -version 2",
            "crm.requisite.preset.list.json",
            '"select":["ID","NAME","ACTIVE","COUNTRY_ID"]',
            "bitrix-direct-requisite-presets-readonly-status.txt",
            "PREVIOUS_PRESET_SCAN_NOT_ACCEPTED",
            "PRESET_COUNT_CHANGED",
            "PRESET_FIELD_FORMAT_INVALID",
            "DUPLICATE_PRESET_ID",
            "DIRECT_BITRIX_PRESET_DETAILS=PASS",
            "WEBHOOK_SAVED=NO",
            "CRM_WRITES=NO",
            "ONEC_CALLS=NO",
            "CUSTOMER_DATA_EXPORTED=NO",
            "-AsSecureString",
            "ZeroFreeBSTR",
        ):
            self.assertIn(term,code)
        for term in (
            "crm.item.add",
            "crm.requisite.add",
            "crm.item.update",
            "crm.item.delete",
            "crm.requisite.delete",
            "Invoke-WebRequest",
            "RegisterTaskDefinition(",
        ):
            self.assertNotIn(term,code)

    def test_json1_extraction_rows(self):
        conn=sqlite3.connect(":memory:")
        sample='{"result":[{"ID":"1","NAME":"Юрлицо","ACTIVE":"Y","COUNTRY_ID":1},{"ID":"2","NAME":"Физлицо","ACTIVE":"Y","COUNTRY_ID":1},{"ID":"3","NAME":"Другая","ACTIVE":"N","COUNTRY_ID":0}]}'
        query="""WITH j(doc) AS (SELECT ?), a AS (
            SELECT CAST(json_extract(p.value,'$.ID') AS TEXT)||'|'||
             hex(CAST(coalesce(json_extract(p.value,'$.NAME'),'') AS BLOB))||'|'||
             coalesce(CAST(json_extract(p.value,'$.ACTIVE') AS TEXT),'UNKNOWN')||'|'||
             coalesce(CAST(json_extract(p.value,'$.COUNTRY_ID') AS TEXT),'UNKNOWN') AS row
            FROM j,json_each(j.doc,'$.result') p
        ) SELECT row FROM a"""
        rows=[v[0] for v in conn.execute(query,(sample,))]
        self.assertEqual(len(rows),3)
        self.assertIn("Юрлицо",bytes.fromhex(rows[0].split("|")[1]).decode("utf-8"))
        conn.close()

if __name__=="__main__":
    unittest.main()

"""Offline contract for one-shot Bitrix24 requisite preset discovery."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]/"bin"

class PresetDiscovery(unittest.TestCase):
    def test_rest_preset_discovery_only(self):
        s=(ROOT/"probe-bitrix-direct-requisite-presets-readonly.ps1").read_text("ascii")
        for term in ("#requires -version 2", "crm.requisite.preset.list.json",
                     '"select":["ID","NAME","ACTIVE","COUNTRY_ID"]',
                     "DIRECT_BITRIX_REQUISITE_PRESETS_READ=PASS",
                     "WEBHOOK_SAVED=NO", "CRM_WRITES=NO",
                     "CUSTOMER_DATA_EXPORTED=NO","-AsSecureString",
                     "ZeroFreeBSTR", "SOURCE_SIZE" if False else "JSON_SIZE"):
            self.assertIn(term,s)
        for term in ("crm.item.add", "crm.item.delete", "crm.requisite.add",
                     "crm.requisite.delete", "Invoke-WebRequest", "ConvertFrom-Json"):
            self.assertNotIn(term,s)

if __name__=="__main__":
    unittest.main()

"""Offline contract for one-shot company/contact CRM-read probes."""
from pathlib import Path
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"

class DirectCrmContactProbe(unittest.TestCase):
    def test_contact_read_only_contract(self):
        s=(BIN/"probe-bitrix-direct-contact-readonly.ps1").read_text(encoding="utf-8")
        self.assertTrue(s.isascii())
        for value in (
            '#requires -version 2', '"entityTypeId":3',
            'crm.item.list.json', '"select":["id"]', '"start":0',
            'bitrix-direct-contact-readonly-status.txt',
            'DIRECT_BITRIX_CRM_CONTACT_READ=PASS',
            'ENTITY_TYPE=CONTACT',
            'WEBHOOK_SAVED=NO',
            'CRM_WRITES=NO',
            'ONEC_CALLS=NO',
            'CUSTOMER_DATA_EXPORTED=NO',
            'Read-Host', '-AsSecureString',
            'SecureStringToBSTR', 'ZeroFreeBSTR',
            'JSON_SIZE', 'HTTP_NOT_200', 'NO_AUTOMATIC_RETRY=YES',
        ):
            self.assertIn(value,s)
        for forbidden in (
            'crm.item.add', 'crm.item.update',
            'crm.company.add', 'crm.contact.add',
            'crm.item.delete', 'crm.contact.delete',
            'Invoke-WebRequest', 'RegisterTaskDefinition(',
            'System.Web.Extensions', 'JavaScriptSerializer',
        ):
            self.assertNotIn(forbidden,s)
    def test_company_probe_remains_unchanged(self):
        s=(BIN/"probe-bitrix-direct-crm-readonly.ps1").read_text(encoding="utf-8")
        self.assertIn('"entityTypeId":4',s)
        self.assertIn("ENTITY_TYPE=COMPANY",s)

if __name__=="__main__":
    unittest.main()

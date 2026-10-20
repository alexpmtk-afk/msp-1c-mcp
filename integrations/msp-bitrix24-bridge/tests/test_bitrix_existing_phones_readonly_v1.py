"""Read-only CRM fm phone-field sample contract after accepted SRV-local 4068 phone source rows."""
from pathlib import Path
import unittest
import hashlib
P=Path(__file__).resolve().parents[1]/"bin"/"probe-bitrix-existing-phones-readonly-v1.ps1"
class BitrixExistingPhonesPilot(unittest.TestCase):
 def test_readonly_two_types_only(self):
  s=P.read_text("ascii")
  for x in ("#requires -version 2", "LOCAL_SERVICE_REQUIRED", "PS2_X64_REQUIRED", "SOURCE=TEST_NEWBASE",
   "crm.item.get?entityTypeId=", "msp_initial_map", "phone-source-newbase-v1.sqlite",
   "customer-phone-snapshot-v2.status", "STATUS=PASS", "PHONE_DB_NOT_ACCEPTED",
   "crm.item.get", "PhoneShape", "originatorId", "originId", "MSP_ONEC_NEWBASE",
   "json_each(doc", "json_type(doc", "typeId", "PHONE",
   "PILOT_CARDS=2", "CRM_ORIGINS_VERIFIED=2", "CONTACT_PHONE_FIELDS=",
   "COMPANY_PHONE_FIELDS=", "CRM_WRITES=0", "CUSTOMERS_DB_WRITES=0",
   "PHONE_DB_WRITES=0", "PII_EXPORTED=0", "BITRIX_EXISTING_PHONE_FIELDS_READONLY_PILOT_V1"):
   self.assertIn(x,s)
  for banned in ("crm.item.add", "crm.item.update", "crm.requisite.update", "crm.company.update",
    "crm.contact.update", "DELETE FROM", "UPDATE customers", "ALTER TABLE",
    "RegisterTaskDefinition", "Write-Host $reply", "Write-Output $reply", "Write-Output $contact",
    "Write-Output $company", "Write-Output $guids", "Write-Output $ids"):
   self.assertNotIn(banned,s)
  self.assertEqual(s.count("function PhoneShape("),1)
  self.assertEqual(s.count("function SqlRead("),1)
  self.assertNotIn("\r",s)
  print("BITRIX_PHONE_READONLY_PILOT_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

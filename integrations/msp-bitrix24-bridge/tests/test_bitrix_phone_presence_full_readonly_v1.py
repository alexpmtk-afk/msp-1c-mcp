"""Complete 4067 mapped phone-eligible Bitrix cards, read-only and aggregate-only."""
import unittest,hashlib
from pathlib import Path
P=Path(__file__).resolve().parents[1]/"bin"/"audit-bitrix-phone-presence-full-readonly-v1.ps1"
class AuditFullPhonePresence(unittest.TestCase):
 def test_fail_closed_batch_and_provenance(self):
  s=P.read_text("ascii")
  for expected in ("#requires -version 2","LOCAL_SERVICE_ONLY","BUYERS_WITH_SOURCE_PHONE=4067",
    "SOURCE_PHONE_ROWS=4068","CRM_CARDS_VERIFIED=","CRM_PHONE_EMPTY=",
    "CRM_PHONE_PRESENT=","CRM_MULTIPLE_PHONE_CARDS=","CRM_PHONE_FIELDS=",
    "msp_initial_map","phone-source-newbase-v1.sqlite",
    "customer-phone-snapshot-v2.status","bitrix-phone-existing-fields-probe-v1.status",
    "crm.item.get?entityTypeId=","-readonly -batch -bail",
    "GROUP BY m.onec_guid","CRM_CARD_DUPLICATE",
    "json_type(doc","json_each(doc","originatorId","originId",
    "MSP_ONEC_NEWBASE","SOURCE_FILE_MISSING","PHONE_ROWS_COUNT_MISMATCH",
    "for($attempt=1;$attempt -le 3;$attempt++)","-le 20",
    "CRM_WRITES=0","CUSTOMERS_DB_WRITES=0","PHONE_DB_WRITES=0","PII_EXPORTED=0",
    "AUDIT_COUNT_MISMATCH","READ_ALL_MAPPED_CRM_CARDS","NOT_READ_ONLY"):
   self.assertIn(expected,s)
  for forbidden in ("crm.item.add","crm.item.update","crm.requisite.update",
    "crm.contact.update","crm.company.update","INSERT INTO customers","UPDATE customers",
    "ALTER TABLE customers","RegisterTaskDefinition", "Write-Output $reply",
    "Write-Output $raw", "Write-Host $reply","Write-Host $lines",
    "Invoke-Expression","iex "):
   self.assertNotIn(forbidden,s)
  self.assertEqual(s.count("function AuditBatch("),1)
  self.assertEqual(s.count("function FetchReadOnly("),1)
  self.assertNotIn("\r",s)
  print("FULL_BITRIX_PHONE_READONLY_WORKER_SHA256="+hashlib.sha256(P.read_bytes()).hexdigest())
if __name__=="__main__":unittest.main()

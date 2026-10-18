"""Read-only contact-info metadata survey: safety and no private-data export."""
from pathlib import Path
import unittest
class ContactMeta(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.s=(Path(__file__).resolve().parents[1]/"bin"/"probe-newbase-contactinfo-metadata-readonly-v1.ps1").read_text("ascii")
 def test_only_local_metadata_get(self):
  s=self.s
  for expected in ("#requires -version 2","127.0.0.1:8085/NewBase/odata/standard.odata/$metadata",
"DtdProcessing","CONTACTINFO_SET=YES",
                   "Customer_DATA_EXPORTED=0","PROPERTY_SIGNATURE_INVALID","ENTITY_TYPE_NOT_FOUND",
                   "CONTACTINFO_ENTITY_SET_MISSING","PHONE_PROBE_ALREADY_EXISTS",
                   "SOURCE=TEST_NEWBASE","ONEC_WRITES=0","BITRIX_REQUESTS=0",
                   "$req.Method='GET'","S-1-5-19"):
   if expected.lower().startswith("customer_data"): expected=expected.upper()
   self.assertIn(expected,s)
  for denied in ("$req.Method='POST'","RegisterTaskDefinition","DeleteTask(",
                 "NotifyChangesReceived(", "SelectChanges(", "Insert INTO customers", "crm.item.add?"):
   self.assertNotIn(denied,s)
  self.assertNotIn("\r",s)
 def test_metadata_output_is_schema_only(self):
  s=self.s
  self.assertIn("FIELD='+ (SafeName",s)
  self.assertIn("NAV='+ (SafeName",s)
  self.assertIn("METADATA_REPORT=",s)
  self.assertIn("CONTACTINFO_METADATA_READONLY",s)
if __name__=="__main__":unittest.main()

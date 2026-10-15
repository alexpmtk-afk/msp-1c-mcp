"""Offline safety contracts: excludes live Bitrix and 1C data access."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT/"bin"
def read(name):return (BIN/name).read_text(encoding="utf-8-sig")
class BootstrapSafety(unittest.TestCase):
    def test_no_live_features_by_default(self):
        s=(ROOT/"config/bridge.ini").read_text(encoding="ascii")
        for k in ("ACTIVE","CUSTOMERS_READ","PRODUCTS_READ","INVOICES_WRITE"):
            self.assertIn(k+"=0",s)
            self.assertNotIn(k+"=1",s)
    def test_idle_loop_never_networks(self):
        s=read("bridge.ps1")
        for k in ("S-1-5-19","POLICY_INVALID","POLICY_DUPLICATE",
                  "CAPABILITY_NOT_IMPLEMENTED","SAFE_IDLE","CUSTOMERS_SYNC=OFF","WRITES=OFF"):
            self.assertIn(k,s)
        for k in ("Invoke-Expression","Invoke-WebRequest","HttpWebRequest","Start-Process","github.com","crm.company.add"):
            self.assertNotIn(k,s)
    def test_installer_is_machine_owned_and_auto_disabled(self):
        s=read("install-system.ps1")
        for k in ("LOCAL SERVICE","Triggers.Create(8)","Triggers.Create(2)","PT5M","P1D",
                  "ROOT_EXISTS","TASK_EXISTS","CommonApplicationData",
                  "$boot.Enabled=$false","$daily.Enabled=$false"):
            self.assertIn(k,s)
        self.assertNotIn("MspOnecHttpsAgentSystem",s)
    def test_only_metadata_inspection(self):
        s=read("inspect-customers-metadata.ps1")
        for k in ("127.0.0.1:8085/NewBase","'GET'","$metadata",
                  "CUSTOMER_RECORDS_EXPORTED=NO","DATA_WRITES=NO"):
            self.assertIn(k,s)
        for k in ("crm.company.add","crm.contact.add",".Method='POST'","github.com"):
            self.assertNotIn(k,s)
    def test_odata_inventory_ps2_ascii_and_credentials(self):
        s=read("inspect-customers-metadata.ps1")
        self.assertTrue(s.isascii(), "PS2 BOM-less script must be ASCII-only")
        self.assertIn("Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString",s)
        self.assertIn("if ($null -eq $Credential) { Fail 'CREDENTIAL_REQUIRED' }",s)
        self.assertIn("$customerRegex=",s)
        for escaped in (r"\u041A\u043E\u043D\u0442\u0440\u0430\u0433\u0435\u043D",
                        r"\u041F\u0430\u0440\u0442\u043D\u0435\u0440",
                        r"\u041F\u043E\u043A\u0443\u043F\u0430\u0442\u0435\u043B",
                        r"\u041A\u043B\u0438\u0435\u043D\u0442"):
            self.assertIn(escaped,s)
        self.assertIn("$req.Method='GET'",s)
        self.assertIn("$req.AllowAutoRedirect=$false",s)
        self.assertIn("$req.Proxy=$null",s)
    def test_read_only_customer_schema_ps2_ascii(self):
        s=read("inspect-customers-schema.ps1")
        self.assertTrue(s.isascii())
        for token in ("'GET'", "standard.odata/$metadata", "127.0.0.1:8085/NewBase", "$request.Proxy=$null",
                      "$request.AllowAutoRedirect=$false", "COUNTERPARTIES", "COUNTERPARTY_CONTACT_INFO",
                      "CUSTOMER_RECORDS_EXPORTED=NO", "DATA_WRITES=NO",
                      "FIELD=", "KEY=", "ENTITY_TYPE="):
            self.assertIn(token,s)
        for forbidden in ("Invoke-Expression", ".Method='POST'", "crm.company.add",
                          "crm.contact.add","Get-Acl -LiteralPath"):
            self.assertNotIn(forbidden,s)
    def test_readonly_customer_counts_ps2_ascii_only(self):
        s=read("inspect-customers-counts.ps1")
        self.assertTrue(s.isascii())
        for token in ("127.0.0.1:8085/NewBase", "/$count", "$request.Method='GET'",
                      "$request.Proxy=$null", "$request.AllowAutoRedirect=$false",
                      "EscapeDataString", "CUSTOMER_RECORDS_EXPORTED=NO",
                      "DATA_WRITES=NO", "BITRIX_CALLS=NO",
                      "COUNTERPARTIES_TOTAL=", "BUYER_ACTIVE_NOT_DELETED="):
            self.assertIn(token,s)
        for token in (".Method='POST'", "crm.company.add", "Invoke-Expression", "Invoke-WebRequest"):
            self.assertNotIn(token,s)
    def test_readonly_required_fields_counts_ps2(self):
        s=read("inspect-customers-required-counts.ps1")
        self.assertTrue(s.isascii())
        for k in ("127.0.0.1:8085/NewBase", "/$count", "$req.Method='GET'",
                  "$req.Proxy=$null", "$req.AllowAutoRedirect=$false",
                  "EscapeDataString", "BOTH_FIELDS_NONEMPTY=",
                  "WHITESPACE_ONLY_NOT_VALIDATED=YES",
                  "CUSTOMER_RECORDS_EXPORTED=NO", "BITRIX_CALLS=NO", "DATA_WRITES=NO"):
            self.assertIn(k,s)
        for k in ("Invoke-Expression", "Invoke-WebRequest", ".Method='POST'", "crm.company.add"):
            self.assertNotIn(k,s)
    def test_odata_string_filter_probe_ps2_readonly(self):
        s=read("diagnose-customer-string-filters.ps1")
        self.assertTrue(s.isascii())
        for token in ("127.0.0.1:8085/NewBase", "/$count", "$req.Method='GET'",
                      "$req.Proxy=$null", "$req.AllowAutoRedirect=$false",
                      "EscapeDataString", "BASELINE_BUYERS", "FULL_NAME_NE_EMPTY",
                      "INN_NE_EMPTY", "BOTH_NE_EMPTY", "FIELD_FILTER_UNAVAILABLE",
                      "COMBINED_PROBE=SKIPPED", "CUSTOMER_RECORDS_EXPORTED=NO",
                      "RAW_IDENTIFIERS_EXPORTED=NO", "DATA_WRITES=NO",
                      "BITRIX_CALLS=NO"):
            self.assertIn(token,s)
        for token in (".Method='POST'", "crm.company.add", "Invoke-Expression", "Invoke-WebRequest"):
            self.assertNotIn(token,s)
    def test_all_odata_probes_require_password_only_ps2(self):
        for name in ("inspect-customers-metadata.ps1",
                     "inspect-customers-schema.ps1", "inspect-customers-counts.ps1",
                     "inspect-customers-required-counts.ps1",
                     "diagnose-customer-string-filters.ps1"):
            s=read(name)
            self.assertTrue(s.isascii(), name)
            self.assertIn("Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString", s)
            self.assertIn("New-Object System.Management.Automation.PSCredential", s)
            self.assertIn("@('MCP_OData_ReadOnly',$secure)", s)
            self.assertIn("ODATA_USERNAME_MISMATCH", s)
            self.assertNotIn("Get-Credential", s)
            self.assertNotIn("-UserName", s)
    def test_local_ten_row_pilot_ps2_and_data_guard(self):
        s=read("pilot-customers-local-10.ps1")
        self.assertTrue(s.isascii())
        for token in ("127.0.0.1:8085/NewBase", "&$top=10", "&$select=",
                      "Ref_Key", "Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString",
                      "$req.Method='GET'", "AllowAutoRedirect=$false", "$req.Proxy=$null",
                      "RESPONSE_TOO_LARGE", "PILOT_ONLY=YES", "CUSTOMER_RECORDS_EXPORTED=NO",
                      "RAW_IDENTIFIERS_EXPORTED=NO", "DATA_WRITES=NO", "BITRIX_CALLS=NO"):
            self.assertIn(token,s)
        for forbidden in ("Get-Credential", "Invoke-Expression", ".Method='POST'",
                          "crm.company.add", "WriteAllText", "Export-Csv"):
            self.assertNotIn(forbidden,s)
    def test_readonly_full_scan_limited_ps2(self):
        s=read("scan-customers-required-fields.ps1")
        self.assertTrue(s.isascii())
        for token in ("127.0.0.1:8085/NewBase", "$top=100", "BASELINE_COUNT_CHANGED",
                      "&$skip=", "&$orderby=Ref_Key%20asc", "ReadPage $filter $skip $top $selected",
                      "DUPLICATE_GUID_ACROSS_PAGES", "FINAL_COUNT_OR_UNIQUENESS_MISMATCH",
                      "COUNT_POSTCHECK", "PAGE_TOO_LARGE", "PAGE_COUNT_LIMIT",
                      "Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString",
                      "CUSTOMER_RECORDS_EXPORTED=NO", "RAW_IDENTIFIERS_EXPORTED=NO",
                      "DATA_WRITES=NO", "BITRIX_CALLS=NO", "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(token,s)
        for token in ("Get-Credential", "Invoke-Expression", "Invoke-WebRequest",
                      "Export-Csv", "WriteAllText", ".Method='POST'", "crm.company.add"):
            self.assertNotIn(token,s)
    def test_rollback_is_task_specific(self):
        s=read("rollback-system.ps1")
        self.assertIn("MspBitrix24Bridge",s)
        self.assertIn("$t.Enabled=$false",s)
        self.assertNotIn("DeleteTask",s)
        self.assertNotIn("Remove-Item",s)
if __name__=="__main__":unittest.main()

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
    def test_buyer_category_probe_100_ps2_readonly(self):
        s=read("pilot-buyer-types-local-100.ps1")
        self.assertTrue(s.isascii())
        for marker in ("127.0.0.1:8085/NewBase", "&$top=100",
                       "Ref_Key", "Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString",
                       "AllowAutoRedirect=$false", "$req.Proxy=$null", "$req.Method='GET'",
                       "DUPLICATE_GUID", "RESPONSE_TOO_LARGE", "SAMPLE_ONLY=YES",
                       "POPULATION_CLASSIFICATION=NOT_YET",
                       "CUSTOMER_RECORDS_EXPORTED=NO", "RAW_IDENTIFIERS_EXPORTED=NO",
                       "DATA_WRITES=NO", "BITRIX_CALLS=NO"):
            self.assertIn(marker,s)
        for forbidden in ("Get-Credential", "Invoke-Expression", "Invoke-WebRequest",
                          "WriteAllText", "Export-Csv", ".Method='POST'", "crm.company.add"):
            self.assertNotIn(forbidden,s)
    def test_buyer_category_count_probes_are_readonly_ps2(self):
        s=read("count-buyer-classes.ps1")
        self.assertTrue(s.isascii())
        for marker in ("127.0.0.1:8085/NewBase", "/$count", "EscapeDataString",
                       "$req.Method='GET'", "$req.Proxy=$null", "$req.AllowAutoRedirect=$false",
                       "Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString",
                       "LEGAL_ENTITIES", "NATURAL_PERSONS", "LEGAL_WITH_NONEMPTY_INN",
                       "BASELINE_MISMATCH", "CATEGORY_FILTER_UNAVAILABLE",
                       "CUSTOMER_RECORDS_EXPORTED=NO", "RAW_IDENTIFIERS_EXPORTED=NO",
                       "BITRIX_CALLS=NO", "SAFE_IDLE_TASK_UNCHANGED=YES",
                       "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(marker,s)
        for forbidden in ("Get-Credential", "Invoke-Expression", "Invoke-WebRequest",
                          "WriteAllText", "Export-Csv", ".Method='POST'", "crm.company.add"):
            self.assertNotIn(forbidden,s)
    def test_legal_only_paged_counts_ps2(self):
        s=read("scan-legal-required-fields.ps1")
        self.assertTrue(s.isascii())
        for token in ("127.0.0.1:8085/NewBase", "$top=100", "&$skip=",
                      "LEGAL_BASELINE_COUNT_CHANGED", "LEGAL_INN_BASELINE_CHANGED",
                      "DUPLICATE_GUID_ACROSS_PAGES", "FINAL_COUNT_OR_UNIQUENESS_MISMATCH",
                      "LEGAL_WITH_BOTH_REQUIRED=", "SCAN_ELAPSED_SECONDS=",
                      "PAGE_REQUEST_MAX_MS=", "Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString",
                      "ORGANIZATION_CLASSIFICATION=LEGAL_ONLY", "CUSTOMER_RECORDS_EXPORTED=NO",
                      "BITRIX_CALLS=NO", "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(token,s)
        for banned in ("Get-Credential", "Invoke-Expression", "Invoke-WebRequest",
                       "Export-Csv", "WriteAllText", ".Method='POST'", "crm.company.add"):
            self.assertNotIn(banned,s)
    def test_customer_scope_includes_natural_persons_without_inn(self):
        spec=(ROOT/"docs/CUSTOMER_SCOPE_POLICY.md").read_text(encoding="utf-8")
        for must in ("CUSTOMER_SCOPE=ALL_ACTIVE_BUYERS",
                     "ALL_ACTIVE_BUYERS_INCLUDED", "INN_REQUIRED=NO",
                     "TYPE_REVIEW_REQUIRED", "1,941", "4,486", "6,433",
                     "ФизическоеЛицо", "ЮридическоеЛицо",
                     "MspBitrix24Bridge", "SAFE_IDLE"):
            self.assertIn(must,spec)
        self.assertNotIn("CUSTOMER_SCOPE=LEGAL_ONLY",spec)
    def test_selected_option_b_covers_all_buyers_and_safe_idle(self):
        spec=(ROOT/"docs/SYNC_ARCHITECTURE_OPTION_B.md").read_text(encoding="utf-8")
        for term in ("Option B", "6,433", "ФизическоеЛицо",
                     "INN", "SQLite", "customers.db", "change_inbox",
                     "bitrix_outbox", "bitrix_links", "SAFE_IDLE",
                     "NOT been created"):
            self.assertIn(term,spec)
        self.assertIn("NOT been proven",spec)
        self.assertIn("no 1C writes",spec)
    def test_external_search_is_on_demand_not_bulk_sync(self):
        spec=(ROOT/"docs/BITRIX_ALWAYS_SEARCHABLE_DIRECTORY.md").read_text(encoding="utf-8")
        for token in ("CRM_DETAIL_SEARCH", "crmShowFoundEntities",
                      "onCrmEntityIsNeedToCreate", "crmShowCreatedEntity",
                      "3 characters", "6,433", "Bitrix24 CRM",
                      "natural persons with no INN", "outbound HTTPS poll",
                      "NOT solved yet", "never scans all buyer rows"):
            self.assertIn(token,spec)
        self.assertIn("No sync activation",spec)
    def test_srv_first_sqlite_schema_and_ps2_preflight(self):
        import sqlite3
        schema=(ROOT/"schema/customer-store.sql").read_text(encoding="utf-8")
        con=sqlite3.connect(":memory:")
        try:
            con.executescript(schema)
            tables={r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            for name in ("customers", "change_inbox", "ingestion_checkpoint", "scan_runs"):
                self.assertIn(name,tables)
            con.execute("INSERT INTO customers(onec_guid,onec_type,buyer,deletion_mark,invalid,updated_at_utc,needs_review) VALUES (?,?,?,?,?,?,?)",
                        ("00000000-0000-0000-0000-000000000001","PERSON",1,0,0,"2026-10-15T00:00:00Z",0))
            self.assertIsNone(con.execute("SELECT inn FROM customers").fetchone()[0])
        finally:
            con.close()
        script=read("preflight-srv-customer-store.ps1")
        self.assertTrue(script.isascii())
        for token in ("127.0.0.1:8085/NewBase", "'GET'", "$metadata",
                      "ExchangePlan_", "CUSTOMER_DB_EXISTS=", "SQLITE_PROVIDER_PRESENT=",
                      "SQLITE_CLI_PRESENT=", "SAFE_IDLE_VERIFIED=YES",
                      "Read-Host -Prompt 'Password for MCP_OData_ReadOnly' -AsSecureString",
                      "CUSTOMER_RECORDS_EXPORTED=NO", "FILES_CREATED=NO", "DATA_WRITES=NO"):
            self.assertIn(token,script)
        for token in (".Method='POST'", "Invoke-Expression", "Export-Csv",
                      "WriteAllBytes", "CreateDirectory", "crm.company.add"):
            self.assertNotIn(token,script)
    def test_srv_sqlite_inventory_no_mutation_ps2(self):
        s=read("inventory-srv-sqlite-runtime.ps1")
        self.assertTrue(s.isascii())
        for token in ("SRV_STORAGE_RUNTIME_INVENTORY","BRIDGE_SQLITE_CLI_PRESENT=",
                      "BRIDGE_SQLITE_PROVIDER_PRESENT=", "PROCESS_BITS=",
                      "OS_VERSION=", "NET35_REGISTRY=", "CUSTOMER_DB_ALREADY_EXISTS=",
                      "SAFE_IDLE=YES", "EXISTING_SQLITE_BINARY_EXECUTED=NO",
                      "FILES_CREATED=NO", "DATA_WRITES=NO"):
            self.assertIn(token,s)
        for forbidden in ("Start-Process", "Invoke-Expression", "WriteAllBytes",
                          "CreateDirectory", "Set-Acl", "New-Item", ".Method='POST'"):
            self.assertNotIn(forbidden,s)
    def test_machine_owned_runtime_policy_and_retired_profile_pilot(self):
        spec=(ROOT/"docs/MACHINE_OWNED_STORAGE_POLICY.md").read_text(encoding="utf-8")
        for token in ("C:\\ProgramData\\MspBitrix24Bridge", "S-1-5-19",
                      "LOCAL SERVICE", "SQLite", "SAFE_IDLE", "DO NOT RUN"):
            self.assertIn(token, spec)
        s=read("pilot-create-sqlite-store.ps1")
        self.assertTrue(s.isascii())
        self.assertTrue(s.startswith("#requires -version 2"))
        self.assertIn("DEPRECATED_USER_PROFILE_INSTALL_FORBIDDEN",s)
        for token in ("CreateDirectory", "Download", "CopyHere",
                      "LOCALAPPDATA", "APPDATA", "C:\\Users\\parshin"):
            self.assertNotIn(token,s)
        for token in ("ACTIVE=0", "CUSTOMERS_READ=0", "PRODUCTS_READ=0",
                      "INVOICES_WRITE=0"):
            conf=(ROOT/"config/bridge.ini").read_text(encoding="ascii")
            self.assertIn(token,conf)
    def test_standalone_machine_collector_audit_ps2_no_changes(self):
        script=read("audit-machine-owned-customer-chain.ps1")
        self.assertTrue(script.isascii())
        for token in ("C:\\ProgramData\\MspCustomerStore", "MspCustomerStoreSync",
                      "S-1-5-19", "MspBitrix24Bridge",
                      "EXISTING_BRIDGE_POLICY=SAFE_IDLE",
                      "COLLECTOR_DB_PRESENT=", "COLLECTOR_CURL_PRESENT=",
                      "COLLECTOR_CA_PRESENT=", "COLLECTOR_BACKUP_MACHINE_OWNED_REQUIRED=YES",
                      "FILES_CREATED=NO", "DATA_WRITES=NO", "TASK_CHANGES=NO",
                      "ONEC_CALLS=NO", "BITRIX_CALLS=NO"):
            self.assertIn(token,script)
        for forbidden in ("CreateDirectory(", "Copy-Item", "New-Item",
                          "Set-Acl", "Set-Content", "WriteAllText(", "RegisterTaskDefinition(",
                          "Start-Process", "Invoke-Expression", ".Method='POST'", "Get-Credential"):
            self.assertNotIn(forbidden,script)
    def test_collector_machine_owned_separate_from_bitrix_idle(self):
        pol=(ROOT/"docs/MACHINE_OWNED_STORAGE_POLICY.md").read_text(encoding="utf-8")
        for marker in ("C:\\ProgramData\\MspCustomerStore", "MspCustomerStoreSync",
                       "S-1-5-19", "SAFE_IDLE", "backups", "secrets",
                       "C:\\ProgramData\\MspBitrix24Bridge"):
            self.assertIn(marker,pol)
    def test_service_owned_empty_smoke_never_calls_onec(self):
        s=read("smoke-customer-store-service.ps1")
        self.assertTrue(s.isascii())
        for term in ("S-1-5-19", "C:\\ProgramData\\MspCustomerStore",
                     "PRAGMA quick_check", "ROLLBACK;", "CUSTOMERS_COUNT=0",
                     "ONEC_CALLS=NO", "BITRIX_CALLS=NO",
                     "STATUS=EMPTY_DB_PASS", "SCHEMA_TABLES=4"):
            self.assertIn(term,s)
        for banned in ("C:\\Users\\", "Invoke-WebRequest", "HttpWebRequest",
                       "Get-Credential", "RegisterTaskDefinition", "crm.company.add"):
            self.assertNotIn(banned,s)
        cfg=(ROOT/"config/collector.ini").read_text(encoding="ascii")
        for key in ("ACTIVE=0", "ONEC_READ=0", "DELTA_READ=0", "BITRIX=0"):
            self.assertIn(key,cfg)
    def test_machine_installer_acl_tls_service_smoke(self):
        s=read("install-machine-customer-store.ps1")
        self.assertTrue(s.isascii())
        for required in ("MspCustomerStore", "MspCustomerStoreSync",
                         "SQLITE_OFFICIAL_ZIP_HASH_MISMATCH", "fae9efccf4469ca69be5d418fc088593cdb86e07a1b211bdb85463591a923b02",
                         "PINNED_SOURCE_HASH_MISMATCH", "S-1-5-19",
                         "'*S-1-5-19:(OI)(CI)RX'", "'*S-1-5-19:(OI)(CI)M'",
                         "$boot.Enabled=$false", "SERVICE_SMOKE_NOT_CONFIRMED",
                         "TLS_RUNTIME_MACHINE_OWNED=YES", "ONEC_CALLS=NO",
                         "BITRIX_CALLS=NO", "PREVIOUS_BRIDGE_UNCHANGED=YES"):
            self.assertIn(required,s)
        for forbidden in ("C:\\Users\\parshin", "Set-ExecutionPolicy", ".Method='POST'",
                          "Enable-NetFirewallRule", "MspOnecHttpsAgentSystem",
                          "Set-Service", "Import-Module", "Get-Credential"):
            self.assertNotIn(forbidden,s)
    def test_partial_machine_install_diagnostic_is_readonly(self):
        s=read("diagnose-machine-store-install-failure.ps1")
        self.assertTrue(s.isascii())
        for marker in ("C:\\ProgramData\\MspCustomerStore", "CUSTOMER_ROOT",
                       "ACL_PROTECTED=", "WRITE_ACE=", "ICACLS_EXISTS=",
                       "COLLECTOR_TASK_EXISTS=", "SQLITE_EXE_PRESENT=",
                       "ACL_CHANGES=NO", "FILE_WRITES=NO", "TASK_CHANGES=NO",
                       "ONEC_CALLS=NO", "BITRIX_CALLS=NO", "NO_INSTALL_RETRY=YES"):
            self.assertIn(marker,s)
        for forbidden in ("CreateDirectory(", "New-Item", "Set-Acl", "Set-Content",
                          "WriteAllText(", "Copy-Item", "RegisterTaskDefinition(",
                          "icacls.exe' /", "Invoke-WebRequest", "Get-Credential"):
            self.assertNotIn(forbidden,s)
    def test_rollback_is_task_specific(self):
        s=read("rollback-system.ps1")
        self.assertIn("MspBitrix24Bridge",s)
        self.assertIn("$t.Enabled=$false",s)
        self.assertNotIn("DeleteTask",s)
        self.assertNotIn("Remove-Item",s)
if __name__=="__main__":unittest.main()

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
                     "S3-accepted machine-owned path"):
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
        self.assertIn("& $installedCurl --version",s)
        self.assertNotIn("& $installedCurl -version",s)
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
    def test_partial_installer_tls_diagnostic_readonly_ps2(self):
        s=read("diagnose-machine-store-tls-block.ps1")
        self.assertTrue(s.isascii())
        for token in ("C:\\ProgramData\\MspCustomerStore",
                      "InspectFile 'TARGET_CA'", "ExecVersion 'TARGET_CURL'",
                      "TLS_DLL_MISSING_COUNT=", "SOURCE_DLL_COUNT=",
                      "CURL_COPY_HASH_MATCH=", "SQLITE_ZIP_PRESENT=",
                      "FILES_WRITTEN=NO", "ACL_CHANGES=NO",
                      "TASK_CHANGES=NO", "INSTALL_RETRY=NO"):
            self.assertIn(token,s)
        for forbidden in ("WriteAllText(", "CreateDirectory(", "Copy-Item",
                          "RegisterTaskDefinition(", "Set-Acl",
                          "Invoke-WebRequest", ".Method='POST'"):
            self.assertNotIn(forbidden,s)
    def test_store_resume_requires_exact_partial_state_and_service_smoke(self):
        s=read("resume-machine-customer-store.ps1")
        self.assertTrue(s.isascii())
        for must in ("C:\\ProgramData\\MspCustomerStore",
                     "UNEXPECTED_FILE_OR_DIRECTORY", "STAGING_FILE_COLLISION",
                     "CURL_SYSTEM_VERSION=PASS", "SQLITE_ZIP_SHA256_MISMATCH",
                     "SOURCE_SHA256_MISMATCH", "MspCustomerStoreSync",
                     "S-1-5-19", "$boot.Enabled=$false",
                     "RUN_SERVICE_EMPTY_SMOKE", "DB_QUICK_CHECK=ok",
                     "CUSTOMERS_COUNT=0", "RUNTIME_DEPENDENCY_USER_PROFILE=NO",
                     "ONEC_CALLS=NO", "BITRIX_CALLS=NO", "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(must,s)
        self.assertIn("& $curl --version",s)
        self.assertNotIn("& $curl -version",s)
        for forbidden in ("DeleteTask", "Remove-Item", "Set-Acl", "MspOnecHttpsAgentSystem",
                          "Get-Credential", "Start-Service", "crm.company.add", "C:\\Users\\parshin"):
            self.assertNotIn(forbidden,s)
    def test_zip_resume_does_not_redownload_or_change_existing_install(self):
        s=read("resume-machine-customer-store-from-zip.ps1")
        self.assertTrue(s.isascii())
        for token in ("VERIFIED_ZIP_NOT_PRESENT", "SQLITE_ARCHIVE_REUSED=YES",
                      "SQLITE_ZIP_SHA256_MISMATCH", "SQLITE_ZIP_ENTRY_LAYOUT=",
                      "$top.GetFolder", "$nestedFolder.ParseName('sqlite3.exe')",
                      "MULTIPLE_SQLITE_EXE_ENTRIES",
                      "MspCustomerStoreSync", "S-1-5-19",
                      "$boot.Enabled=$false", "RUN_SERVICE_EMPTY_SMOKE",
                      "CUSTOMERS_COUNT=0", "EXISTING_BRIDGE_CHANGED=NO",
                      "ONEC_CALLS=NO", "BITRIX_CALLS=NO",
                      "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(token,s)
        self.assertNotIn("Fetch 'https://www.sqlite.org/",s)
        for forbidden in ("Remove-Item", "DeleteTask", "Set-Acl",
                          "MspOnecHttpsAgentSystem", "Get-Credential", "crm.company.add"):
            self.assertNotIn(forbidden,s)
    def test_schema_lf_resume_offline_and_service_only(self):
        s=read("resume-machine-customer-store-from-schema.ps1")
        self.assertTrue(s.isascii())
        for term in ("PINNED_STAGED_SQL_SHA256=PASS",
                     "50748aada5273f60a8056cb1358334cf3fe3c221b67ca8766c8d18a9003b30a3",
                     "SCHEMA_COPY_SHA256=PASS", "SQL_TARGET_COLLISION",
                     "LOCAL_SERVICE_WRITABLE_ACL_MISSING",
                     "UNEXPECTED_ITEM", "MspCustomerStoreSync", "S-1-5-19",
                     "$boot.Enabled=$false", "SERVICE_EMPTY_SMOKE=PASS",
                     "CUSTOMERS_COUNT=0", "COLLECTOR_BOOT_TRIGGER_ENABLED=NO",
                     "ONEC_CALLS=NO", "BITRIX_CALLS=NO"):
            self.assertIn(term,s)
        for forbidden in ("Invoke-WebRequest", "raw.githubusercontent.com", "Set-Acl",
                          "Remove-Item", "DeleteTask", "Get-Credential", "crm.company.add"):
            self.assertNotIn(forbidden,s)
    def test_raw_lf_schema_checksum_enforced(self):
        attr=(ROOT/".gitattributes").read_text(encoding="ascii")
        self.assertIn("schema/*.sql text eol=lf",attr)
        self.assertIn("bin/*.ps1 text eol=lf",attr)
        self.assertIn("config/*.ini text eol=lf",attr)
        for file in ("resume-machine-customer-store.ps1",
                     "resume-machine-customer-store-from-zip.ps1",
                     "resume-machine-customer-store-from-schema.ps1"):
            s=read(file)
            self.assertIn("50748aada5273f60a8056cb1358334cf3fe3c221b67ca8766c8d18a9003b30a3",s)
        import hashlib
        raw=(ROOT/"schema/customer-store.sql").read_bytes()
        self.assertNotIn(b"\r",raw)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),
                         "50748aada5273f60a8056cb1358334cf3fe3c221b67ca8766c8d18a9003b30a3")
    def test_schema_failure_diagnostic_is_readonly(self):
        s=read("diagnose-customer-store-schema-failure.ps1")
        self.assertTrue(s.isascii())
        for token in ("SCHEMA_IN_MEMORY", "DB_READONLY", "MspCustomerStoreSync",
                      "TASK_LAST_RESULT=", "SQL_SCHEMA_PRESENT=YES",
                      "SMOKE_STATE_GATE=", "SMOKE_STATE_PHASE=",
                      "LOCAL_SERVICE_READ_ACE=", "LOCAL_SERVICE_WRITE_ACE=",
                      "FILES_CREATED=NO", "ACL_CHANGES=NO",
                      "TASK_CHANGES=NO", "ONEC_CALLS=NO", "BITRIX_CALLS=NO"):
            self.assertIn(token,s)
        self.assertIn("-batch -bail :memory:",s)
        self.assertIn("-readonly",s)
        for forbidden in ("CreateDirectory(", "WriteAllText(", "Copy-Item", "New-Item",
                          "RegisterTaskDefinition(", "Invoke-WebRequest", "crm.company.add"):
            self.assertNotIn(forbidden,s)
    def test_service_sqlite_dot_read_windows_forward_slashes(self):
        s=read("smoke-customer-store-service.ps1")
        self.assertIn("$schema.Replace('\\','/')",s)
        self.assertIn("$command='.read '+",s)
        self.assertNotIn("$command='.read \"'",s)
        self.assertIn("$id.User.Value -ne 'S-1-5-19'",s)
        self.assertIn("STATUS=EMPTY_DB_PASS",s)
        self.assertIn("ROLLBACK;",s)
    def test_schema_path_repair_preserves_machine_task_and_data(self):
        s=read("repair-customer-store-schema-path.ps1")
        self.assertTrue(s.isascii())
        for term in ("S-1-5-19", "MspCustomerStoreSync",
                     "SQLITE_MEMORY_SCHEMA_PATH=PASS", "STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=SCHEMA",
                     "smoke-before-schema-path-fix.ps1.bak",
                     "smoke-schema-path-fixed.ps1.new", "[IO.File]::Replace",
                     "56f6d629241380828563cdf8551fefb1b53fbb71aeb06cfa4e2ab4a71ad3131d",
                     "b2753f937e1e2c941440b69cbb2596655909f7a11892c61d34e44aa95c49b388",
                     "COLLECTOR_BOOT_AUTOSTART=OFF", "CUSTOMERS_COUNT=0",
                     "TASK_DEFINITION_CHANGED=NO", "ONEC_CALLS=NO",
                     "BITRIX_CALLS=NO", "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(term,s)
        for forbidden in ("RegisterTaskDefinition(", "DeleteTask", "Set-Acl",
                          "Remove-Item", "Get-Credential", "MspOnecHttpsAgentSystem"):
            self.assertNotIn(forbidden,s)
    def test_machine_service_1c_probe_readonly_and_dpapi(self):
        s=read("probe-onec-service-readonly.ps1")
        self.assertTrue(s.isascii())
        for term in ("S-1-5-19", "LocalMachine", "ProtectedData",
                     "MCP_OData_ReadOnly", "127.0.0.1:8085/NewBase",
                     "$req.Method='GET'", "ACTIVE_BUYER_COUNT=",
                     "CUSTOMER_RECORDS_EXPORTED=NO", "ONEC_WRITES=NO",
                     "BITRIX_CALLS=NO", "STATE=NOT_ENABLED"):
            if term=="STATE=NOT_ENABLED":
                continue
            self.assertIn(term,s)
        for bad in ("C:\\Users\\", "Invoke-WebRequest", "Export-Csv",
                    "Get-Credential", "Method='POST'", "RegisterTaskDefinition"):
            self.assertNotIn(bad,s)
    def test_machine_dpapi_enrollment_is_service_only(self):
        s=read("provision-onec-service-credential.ps1")
        self.assertTrue(s.isascii())
        for value in ("Read-Host -Prompt 'Password for MCP_OData_ReadOnly",
                      "SecureStringToBSTR", "ZeroFreeBSTR",
                      "DataProtectionScope]::LocalMachine",
                      "MspCustomerStoreCredentialProof", "S-1-5-19",
                      "ONEC_PROOF_FAILURE_GATE=", "DeleteTask('MspCustomerStoreCredentialProof'",
                      "CUSTOMER_RECORDS_EXPORTED=NO", "COLLECTOR_AUTOSTART=OFF",
                      "ONEC_WRITES=NO", "BITRIX_CALLS=NO",
                      "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(value,s)
        for value in ("C:\\Users\\parshin", "Get-Credential",
                      "Method='POST'", "MspOnecHttpsAgentSystem",
                      "RegisterTaskDefinition('MspCustomerStoreSync'",
                      "Invoke-Expression"):
            self.assertNotIn(value,s)
    def test_pilot10_machine_owned_customer_transfer(self):
        s=read("pilot-machine-customer-store-10.ps1")
        self.assertTrue(s.isascii())
        for fragment in ("S-1-5-19", "MCP_OData_ReadOnly",
                         "DataProtectionScope]::LocalMachine",
                         "ACTIVE=0", "ONEC_READ=0", "DELTA_READ=0", "BITRIX=0",
                         "PILOT_ROWS=10", "SOURCE_GUID_DUPLICATE", "UTF8.GetBytes",
                         "BEGIN IMMEDIATE;", "COMMIT;", "SQLITE_BACKREAD=PASS",
                         "PRAGMA quick_check", "PILOT_PERSON=", "PILOT_REVIEW=",
                         "CUSTOMER_RECORDS_EXPORTED=NO", "ONEC_WRITES=NO",
                         "BITRIX_CALLS=NO"):
            self.assertIn(fragment,s)
        self.assertNotIn("Get-Credential",s)
        self.assertNotIn("RegisterTaskDefinition",s)
        self.assertNotIn("127.0.0.1:9786",s)
        self.assertNotIn("Method='POST'",s)
        self.assertNotIn("Invoke-WebRequest",s)
    def test_customer_pilot10_runner_safe_one_shot_local_service(self):
        s=read("run-customer-store-pilot10.ps1")
        self.assertTrue(s.isascii())
        for token in ("MspCustomerStorePilot10", "MspCustomerStoreSync",
                      "PILOT_WORKER_SHA256=PASS", "S-1-5-19",
                      "CUSTOMERS_DB_NOT_EMPTY", "PILOT_DB_COUNT_MISMATCH",
                      "PILOT_ONE_TIME_TASK_REMOVED=YES", "COLLECTOR_AUTOSTART=OFF",
                      "EXISTING_TASKS_UNCHANGED=YES", "CUSTOMER_RECORDS_EXPORTED=NO",
                      "ONEC_WRITES=NO", "BITRIX_CALLS=NO", "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(token,s)
        self.assertNotIn("DeleteTask('MspCustomerStoreSync'",s)
        self.assertNotIn("Get-Credential",s)
        self.assertNotIn("Method='POST'",s)
    def test_full_initial_load_6433_atomic_and_source_readonly(self):
        s=read("initial-load-customers-6433.ps1")
        self.assertTrue(s.isascii())
        for item in ("MspCustomerStore", "DataProtectionScope]::LocalMachine",
                     "S-1-5-19", "$r.Method='GET'", "PILOT_PROOF_NOT_PASS",
                     "SOURCE_COUNT_CHANGED", "DUPLICATE_SOURCE_GUID",
                     "PILOT_GUID_DISAPPEARED", "ON CONFLICT(onec_guid) DO UPDATE",
                     "BEGIN IMMEDIATE;", "COMMIT;", "accept_count", "accept_active",
                     "CHECK(n=6433)", "SOURCE_COUNT_CHANGED_DURING_SCAN",
                     "TRANSACTION_TOO_LARGE", "scan_runs", "BACKREAD_COUNTS_FAILED",
                     "DB_ROWS=6433", "DB_UNIQUE_GUIDS=6433",
                     "PILOT_EXISTING_GUIDS_PRESERVED=10",
                     "ONEC_WRITES=NO", "BITRIX_CALLS=NO",
                     "RESULT=PASS;STAGE=SRV_CUSTOMER_STORE_INITIAL_6433"):
            self.assertIn(item,s)
        for forbidden in ("Get-Credential", "WriteAllBytes(", "RegisterTaskDefinition(",
                          "DELETE FROM customers", "DROP TABLE customers",
                          "Method='POST'", "C:\\Users\\parshin",
                          "Invoke-WebRequest", "Raw customer"):
            self.assertNotIn(forbidden,s)
        self.assertIn("UTF8.GetBytes",s)
        self.assertIn("$script:base='http://127.0.0.1:8085/NewBase",s)
    def test_initial_full_load_runner_exactly_one_service_task(self):
        s=read("run-customer-store-initial-6433.ps1")
        self.assertTrue(s.isascii())
        for token in ("MspCustomerStoreInitial6433", "MspCustomerStoreSync",
                      "S-1-5-19", "INITIAL_WORKER_SHA256=PASS",
                      "a06c3c2155434557e9fb106dad820588aefedcf22afec72f9a8ec56ae7eabc98",
                      "EXPECTED_TEN_PILOT_ROWS", "TEMPORARY_TASK_HAS_AUTO_TRIGGER",
                      "FULL_LOAD_FAILURE_PHASE=", "S3_ROWS=6433",
                      "S3_NEW_GUIDS=6423", "S3_EXISTING_PILOT_GUIDS=10",
                      "COLLECTOR_BOOT_AUTOSTART=OFF",
                      "ONEC_WRITES=NO", "BITRIX_CALLS=NO",
                      "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(token,s)
        self.assertNotIn("DeleteTask('MspCustomerStoreSync'",s)
        self.assertNotIn("Get-Credential",s)
        self.assertNotIn("Method='POST'",s)
    def test_numeric_category_counts_format_before_comparison(self):
        worker=read("initial-load-customers-6433.ps1")
        runner=read("run-customer-store-initial-6433.ps1")
        self.assertIn("('{0}:{1}:{2}' -f $legalCount,$personCount,$reviewCount)",worker)
        self.assertIn("('{0}:{1}:{2}' -f $legal,$person,$review)",runner)
        self.assertNotIn("($legalCount+':'+$personCount+':'+$reviewCount)",worker)
        self.assertNotIn("($legal+':'+$person+':'+$review)",runner)
    def test_initial_load_committed_reconciliation_safe_cleanup(self):
        s=read("accept-initial-load-6433-and-cleanup.ps1")
        self.assertTrue(s.isascii())
        for token in ("6433:6433:6433", "1941:4486:6", "DB_QUICK_CHECK_FAILED",
                      "MspCustomerStoreInitial6433", "TEMP_TASK_NOT_READY",
                      "TEMP_TASK_RESULT_UNEXPECTED", "TEMP_TASK_HAS_TRIGGERS",
                      "MspCustomerStoreSync", "S-1-5-19",
                      "STATUS=FAIL;GATE=RUNTIME_ERROR;PHASE=BACKREAD",
                      "COMPLETED_SCAN_RUN_MISSING",
                      "customer-initial-load-accepted.txt",
                      "TEMP_INITIAL_TASK_REMOVED=YES",
                      "ORIGINAL_FAILURE_LOG_PRESERVED=YES", "AUTO_START=OFF",
                      "ONEC_CALLS=NO", "BITRIX_CALLS=NO",
                      "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(token,s)
        self.assertIn("DeleteTask('MspCustomerStoreInitial6433'",s)
        for forbidden in ("DeleteTask('MspCustomerStoreSync'",
                          "RegisterTaskDefinition(", "Set-Acl", "Copy-Item",
                          "Remove-Item", "Invoke-WebRequest", "Method='POST'",
                          "Get-Credential", "C:\\Users\\parshin"):
            self.assertNotIn(forbidden,s)
        self.assertIn("-readonly -batch -bail",s)
        self.assertNotIn("'DELETE FROM customers",s)
    def test_s4_exchange_plan_metadata_service_get_only(self):
        s=read("survey-exchange-plan-metadata-service.ps1")
        self.assertTrue(s.isascii())
        for token in ("DataProtectionScope]::LocalMachine", "S-1-5-19",
                      "MCP_OData_ReadOnly", "ACTIVE=0", "DELTA_READ=0",
                      "$req.Method='GET'", "standard.odata/$metadata",
                      "EXCHANGE_PLANS=", "PLAN_{0:D3}", "SelectChanges",
                      "ConfirmChanges", "EXCHANGE_PLAN_LIMIT",
                      "METADATA_OVER_32M", "ONEC_WRITES=NO", "BITRIX_CALLS=NO",
                      "S4_CHANGE_REGISTRATION_READY=NOT_PROVEN"):
            self.assertIn(token,s)
        for bad in ("$req.Method=\'POST\'", "DeleteTask", "RegisterTaskDefinition",
                    "Get-Credential", "127.0.0.1:9786", "WriteAllText($db",
                    "SELECT count(*) FROM customers"):
            self.assertNotIn(bad,s)
    def test_s4_readonly_option_b_survey_one_shot_task(self):
        s=read("run-exchange-plan-survey.ps1")
        self.assertTrue(s.isascii())
        for token in ("MspCustomerStoreExchangeSurvey", "MspCustomerStoreSync",
                      "S-1-5-19", "S4_GET_PROBE_SHA256=PASS",
                      "492272aa431752620d2a5266166e3387c68bcc9b7748854cf2a5cb01cb94dc79",
                      "S4_6433_CUSTOMER_DB_UNCHANGED=YES",
                      "S4_MAIN_COLLECTOR_AUTOSTART=OFF",
                      "S4_REGISTERED_DELTA=NOT_YET_PROVEN",
                      "S4_EXCHANGE_PLAN_SET_COUNT=", "S4_TEMP_TASK_DELETED=YES",
                      "ONEC_WRITES=NO", "BITRIX_CALLS=NO",
                      "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(token,s)
        self.assertNotIn("DeleteTask('MspCustomerStoreSync'",s)
        self.assertNotIn("Get-Credential",s)
        self.assertNotIn("Method='POST'",s)
    def test_bitrix_search_fts5_schema_build_safe(self):
        s=read("build-bitrix-search-index.ps1")
        self.assertTrue(s.isascii())
        for val in ("S-1-5-19", "CREATE VIRTUAL TABLE customer_search_v1",
                    "tokenize='trigram'", "6433:6433",
                    "BEGIN IMMEDIATE;", "CHECK(n=6433)",
                    "CUSTOMERS_UNCHANGED=6433", "BITRIX_CALLS=NO"):
            self.assertIn(val,s)
        self.assertNotIn("C:\\Users\\parshin",s)
        self.assertNotIn("DeleteTask(",s)
        self.assertNotIn("Method='POST'",s)

    def test_bitrix_search_adapter_bounded_hex_injection_safe(self):
        s=read("query-bitrix-search-index.ps1")
        self.assertTrue(s.isascii())
        for val in ("S-1-5-19", "SearchQuery",
                    "VALIDATESET", "UTF8.GetBytes", "CAST(X'",
                    "customer_search_v1 MATCH", "json_group_array",
                    "ORDER BY c.onec_guid LIMIT ", "EntityType",
                    "-readonly", "GetString($bytes)",
                    "BITRIX_SEARCH_NOT_AVAILABLE"):
            if val=="VALIDATESET":
                val="ValidateSet"
            self.assertIn(val,s)
        self.assertNotIn("RegisterTaskDefinition(",s)
        self.assertNotIn("Method='POST'",s)
        self.assertNotIn("Invoke-WebRequest",s)
        self.assertNotIn("WriteAllText(",s)
    def test_bitrix_index_one_time_service_install_is_gated(self):
        s=read("run-bitrix-search-index-setup.ps1")
        self.assertTrue(s.isascii())
        for item in ("MspCustomerStoreBitrixIndex","MspCustomerStoreSync",
                     "S-1-5-19", "SEARCH_SCRIPT_SHA256=PASS",
                     "INDEX_BUILDER_SHA256=PASS", "SAFE_IDLE_CONFIG_CHANGED",
                     "SEARCH_INDEX_ALREADY_PRESENT", "INDEX_BUILD_NOT_ACCEPTED",
                     "TEMPORARY_INDEX_TASK_REMOVED=YES",
                     "NO_BITRIX_PORTAL_CONNECTION=YES", "CUSTOMER_DATA_EXPORTED=NO",
                     "MAIN_COLLECTOR_AUTOSTART=OFF",
                     "PRE_INDEX_BACKUP_VERIFIED=YES", "BACKUP_INTEGRITY_FAILED",
                     "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(item,s)
        self.assertIn("DeleteTask('MspCustomerStoreBitrixIndex'",s)
        self.assertNotIn("DeleteTask('MspCustomerStoreSync'",s)
        self.assertNotIn("Get-Credential",s)
        self.assertNotIn("Method='POST'",s)
    def test_s4_bitrix_outbound_worker_is_machine_only_and_fail_closed(self):
        worker=read("bitrix-search-outbound-once.ps1")
        adapter=read("query-bitrix-search-index.ps1")
        self.assertTrue(worker.isascii())
        self.assertTrue(adapter.isascii())
        for expected in ("S-1-5-19", "WORKER_NOT_ENABLED",
                         "MspBitrixSearchWorker-v1", "DataProtectionScope]::LocalMachine",
                         "bitrix-search-worker.dpapi", "bitrix-search-worker.ini",
                         "https://vm-817589", "ReadHexQueryFromStandardInput",
                         "OutputUtf8Hex", "Customer", "WORKER_ENDPOINT_NOT_APPROVED",
                         "WORKER_TOKEN_INVALID", "SEARCH_RESULT_MAX=20",
                         "BITRIX_WRITES=NO", "ONEC_CALLS=NO",
                         "NO_AUTOMATIC_RETRY=YES"):
            if expected=="Customer":
                continue
            self.assertIn(expected, worker)
        for forbidden in ("Invoke-WebRequest", "127.0.0.1:8085",
                          "Set-Acl", "RegisterTaskDefinition(", "CreateFile",
                          "WriteAllText(", "C:\\Users\\parshin"):
            self.assertNotIn(forbidden,worker)
        for expected in ("ReadHexQueryFromStandardInput",
                         "OutputUtf8Hex", "QUERY_HEX_INVALID",
                         "DUAL_INPUT_CHANNEL", "UTF8.GetString($termBytes)"):
            self.assertIn(expected,adapter)
        self.assertIn("if($OutputUtf8Hex){[Console]::Out.WriteLine($text)}",adapter)
        self.assertIn("--config -",worker)
        self.assertIn("data-binary = ",worker)

    def test_bitrix_worker_offline_staging_is_non_deploying(self):
        s=read("stage-bitrix-outbound-code.ps1")
        self.assertTrue(s.isascii())
        for expected in ("1c3cf6832bf513a9b5b4f1ac4907bfa85b9b8119f7b91b005e64df4f05fe02f8",
                         "bb2ccf66cbc38c97e9588b22580bd0fcccab1725fffeac665f8f042ca2724c7b",
                         "8820c88eecfc1ffd85d4c6d8cc329f5dc6eca868fe56d45ecc5f49211d2366ff",
                         "S-1-5-19" if False else "MspCustomerStoreSync",
                         "[IO.File]::Replace", "ORIGINAL_ADAPTER_BACKUP=PASS",
                         "OUTBOUND_NETWORK_REQUESTS=NO",
                         "WORKER_CONFIGURATION_CREATED=NO",
                         "WORKER_TASK_REGISTERED=NO",
                         "CUSTOMER_DATA_EXPORTED=NO", "NO_AUTOMATIC_RETRY=YES"):
            self.assertIn(expected,s)
        self.assertNotIn("RegisterTaskDefinition(",s)
        self.assertNotIn("DeleteTask(",s)
        self.assertNotIn("Method='POST'",s)

    def test_bitrix_ps2_local_service_runtime_probe_is_read_only(self):
        s=read("probe-bitrix-worker-runtime-service.ps1")
        self.assertTrue(s.isascii())
        for item in ("S-1-5-19", "System.Web.Extensions",
                     "JavaScriptSerializer", "JSON_UNICODE_ROUNDTRIP",
                     "D0A2D0B5D181D182", "PS2_X64_REQUIRED",
                     "WORKER_ALREADY_CONFIGURED", "WORKER_HASH_MISMATCH",
                     "ADAPTER_HASH_MISMATCH", "customers", "customer_search_v1",
                     "6433:6433", "PRAGMA quick_check", "NETWORK_CALLS=NO",
                     "ONEC_CALLS=NO", "BITRIX_CALLS=NO",
                     "RESULT=PASS;STAGE=SRV_BITRIX_WORKER_RUNTIME_SMOKE"):
            self.assertIn(item,s)
        for item in ("Invoke-WebRequest", "HttpWebRequest", "RegisterTaskDefinition",
                     "DeleteTask(", "WriteAllText($db", "MspOnecHttpsAgentSystem"):
            self.assertNotIn(item,s)

    def test_rollback_is_task_specific(self):
        s=read("rollback-system.ps1")
        self.assertIn("MspBitrix24Bridge",s)
        self.assertIn("$t.Enabled=$false",s)
        self.assertNotIn("DeleteTask",s)
        self.assertNotIn("Remove-Item",s)
if __name__=="__main__":unittest.main()

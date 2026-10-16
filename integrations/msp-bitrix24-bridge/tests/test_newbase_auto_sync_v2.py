"""Autonomous TEST NewBase 1C snapshot and Bitrix24 batch code contracts."""
from pathlib import Path
import unittest
BIN=Path(__file__).resolve().parents[1]/"bin"
class SyncV2(unittest.TestCase):
    def test_full_source_sync_is_only_test_newbase(self):
        s=(BIN/"refresh-newbase-source-v2.ps1").read_text("ascii")
        for t in ("#requires -version 2","/NewBase/odata/standard.odata/",
                  "MspCustomerStore-OnecTest-OData-v1","MCP_OData_ReadOnly",
                  "BEGIN IMMEDIATE;","COMMIT;","msp_auto_outbox",
                  "msp_auto_scan_runs","_incoming","_changed","_missing",
                  "customer_search_v1","SOURCE_COUNT_BEFORE",
                  "SOURCE_COUNT_AFTER","SQLITE_ATOMIC_COMMIT=PASS",
                  "NEWBASE_WRITES=NO","msp-newbase-auto-source-status.txt",
                  "SOURCE_CHANGED_OR_NEW="):
            self.assertIn(t,s)
        for deny in ("crm.item.add","crm.item.delete","crm.requisite.add",
                     "http://192.","crm.item.update","C:\\MCP\\"):
            self.assertNotIn(deny,s)
    def test_dispatch_batched_and_outbox_durable(self):
        core=(BIN/"msp-newbase-bitrix-core-v2.ps1").read_text("ascii")
        worker=(BIN/"pump-newbase-bitrix-batch-v2.ps1").read_text("ascii")
        for token in ("function Batch(","function BResult(","function Secret(",
                      "function MarkDone(","msp_auto_map","msp_auto_ops",
                      "msp_auto_outbox","batch","--cacert",
                      "DataProtectionScope]::LocalMachine"):
            self.assertIn(token,core)
        for token in ("NEWBASE_CRM_BATCH_V2","SOURCE_1C_WRITES=NO",
                      "MSP_ONEC_NEWBASE","MspNewbaseBitrixPumpV2",
                      "crm.item.add?entityTypeId=",
                      "crm.requisite.add?fields[ENTITY_TYPE_ID]=4",
                      "crm.item.get?entityTypeId=",
                      "BATCH_ORIGIN_SEARCH","BATCH_DUPLICATE_SCREEN",
                      "BATCH_COMPANY_CONTACT_ADD","OUTBOX_PROGRESS_PERSISTED=YES",
                      "UNRESOLVED_WRITES="):
            self.assertIn(token,worker)
        for deny in ("crm.item.delete","crm.requisite.delete","/opt/mcp/",
                     "RegisterTaskDefinition","http://127.0.0.1:8085"):
            self.assertNotIn(deny,worker)
        self.assertEqual(worker.count("crm.item.add?entityTypeId="),1)
        self.assertEqual(worker.count("crm.requisite.add?fields[ENTITY_TYPE_ID]"),1)
if __name__=="__main__":
    unittest.main()

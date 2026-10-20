"""Safety & performance contracts for V2 manual-only NewBuyer source discovery."""
from pathlib import Path
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"
WORKER=(BIN/"discover-newbase-new-buyers-v2.ps1").read_text("utf-8")
LAUNCHER=(BIN/"start-newbuyer-discovery-v2.ps1").read_text("utf-8")

class DiscoveryV2(unittest.TestCase):
 def test_count_timeout_and_page_timeout_distinct(self):
  self.assertIn("function Request([string]$Uri,[int]$TimeoutMs=30000)",WORKER)
  self.assertIn("$r.Timeout=$TimeoutMs",WORKER)
  self.assertIn("$r.ReadWriteTimeout=$TimeoutMs",WORKER)
  self.assertEqual(WORKER.count("(Request $uri 90000).GetResponse()"),1)
  self.assertEqual(WORKER.count("(Request $uri).GetResponse()"),1)
  self.assertIn("SOURCE_COUNT_BEFORE",WORKER)
  self.assertIn("SOURCE_COUNT_AFTER",WORKER)
 def test_durable_status_progress_and_failure_without_pii(self):
  for token in ("msp-newbuyer-discovery-v2.status","STATUS=RUNNING;PHASE=PRECHECK",
                "STATUS=RUNNING;PHASE=SOURCE_ALL_PAGES","STATUS=FAIL;PHASE=",
                "STATUS=PASS;SOURCE=TEST_NEWBASE","COUNT_TIMEOUT_MS=90000",
                "EXPECTED='+$expected","GATE='+$gate", "PII_EXPORTED=0",
                "ONEC_WRITES=0","CRM_WRITES=0","AUTO_UPDATE=OFF"):
   self.assertIn(token,WORKER,token)
  self.assertIn("CHECK(n BETWEEN 0 AND 20)",WORKER)
  self.assertIn("msp_newbuyer_queue",WORKER)
  self.assertIn("LEFT JOIN customers",WORKER)
  self.assertIn("6433:6433:6433:0",WORKER)
  self.assertIn("msp_initial_map",WORKER)
  for banned in ("msp_auto_outbox","crm.item.add","crm.item.update",
                 "UPDATE customers SET","DELETE FROM customer_search_v1",
                 "NotifyChangesReceived","SelectChanges","RegisterTaskDefinition"):
   self.assertNotIn(banned,WORKER,banned)
  self.assertEqual(WORKER.count("INSERT INTO customers("),1)
  self.assertEqual(WORKER.count("COMMIT;"),1)
 def test_manual_launcher_pinned_correct_worker_and_no_automatic_trigger(self):
  for token in ("MspNewBuyerDiscoveryV2","MspNewBuyerDiscoveryV1",
                "MspNewBuyerDiagnosticV1","PRIOR_TASK_RUNNING","PT15M",
                "Triggers.Count -ne 0","msp-newbuyer-discovery-v2.status",
                "593114f7fd322e5b92030bbedae66bd125016dbd8931fce4b2a314680b5313eb",
                "6d05b9dc332d9f8b03cab4dac10ab9036fad6cb6",
                "6433:6433:6433:0","SAFE_IDLE","NoProfile","LOCAL"):
   if token=="LOCAL":continue
   self.assertIn(token,LAUNCHER,token)
  self.assertIn("discover-newbase-new-buyers-v2.ps1",LAUNCHER)
  self.assertEqual(LAUNCHER.count("RegisterTaskDefinition("),1)
  self.assertEqual(LAUNCHER.count("$task.Run($null)"),1)
  for bad in ("Triggers.Create(", "Get-WinEvent","crm.item.add","msp_auto_outbox"):
   self.assertNotIn(bad,LAUNCHER)
if __name__=="__main__": unittest.main()

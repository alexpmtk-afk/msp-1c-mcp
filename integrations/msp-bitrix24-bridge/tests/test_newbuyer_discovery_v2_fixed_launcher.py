"""Regression: pinned worker URL and hash must refer to V2, not V1."""
from pathlib import Path
import unittest

BIN=Path(__file__).resolve().parents[1]/"bin"
S=(BIN/"start-newbuyer-discovery-v2-fixed.ps1").read_text("utf-8")

class FixedNewbuyerDiscoveryLauncher(unittest.TestCase):
 def test_fixed_url_and_sha_guard(self):
  expected="https://raw.githubusercontent.com/alexpmtk-afk/msp-1c-mcp/6d05b9dc332d9f8b03cab4dac10ab9036fad6cb6/integrations/msp-bitrix24-bridge/bin/discover-newbase-new-buyers-v2.ps1"
  self.assertIn(expected,S)
  self.assertNotIn("/discover-newbase-new-buyers-v1.ps1",S)
  self.assertIn("593114f7fd322e5b92030bbedae66bd125016dbd8931fce4b2a314680b5313eb",S)
  self.assertIn("WORKER_PATH_VERSION_MISMATCH",S)
  self.assertIn("staging\\msp-newbuyer-discovery-v2-fixed",S)
  self.assertNotIn("staging\\msp-newbuyer-discovery-v2'",S)
 def test_prior_failure_does_not_auto_run_old_task(self):
  for fragment in ("MspNewBuyerDiscoveryV2","MspNewBuyerDiscoveryV1","MspNewBuyerDiagnosticV1",
                   "6433:6433:6433:0","PRIOR_TASK_RUNNING","TRIGGER_NOT_EMPTY",
                   "ONEC_WRITES=0","CRM_WRITES=0","AUTO_UPDATE=OFF"):
   self.assertIn(fragment,S)
  self.assertEqual(S.count("$task.Run($null)"),1)
  self.assertEqual(S.count("RegisterTaskDefinition("),1)
  for bad in ("Triggers.Create(","crm.item.add","crm.item.update","Stop-Process",
              "DeleteTask(", "Unregister-ScheduledTask","UPDATE customers SET"):
   self.assertNotIn(bad,S)
if __name__=="__main__": unittest.main()

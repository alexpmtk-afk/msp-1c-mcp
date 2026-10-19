"""Fail-closed no-trigger SRV x64 PS2 task launcher for one-time phone table migration."""
from pathlib import Path
import hashlib,unittest
P=Path(__file__).resolve().parents[1]/"bin"/"start-srv-customer-phone-unification-v1.ps1"
class CustomerPhoneUnifyLaunch(unittest.TestCase):
 def test_launch_contract(self):
  data=P.read_bytes(); s=data.decode("ascii")
  for needle in ("#requires -version 2", "ADMIN_REQUIRED", "PS2_X64_REQUIRED",
    "MspNewbasePhoneSnapshotLocalV2", "SOURCE_TASK_CONCURRENT",
    "MspCustomerPhoneUnifyV1", "S-1-5-19",
    "UNIFY_WORKER_VERIFIED=PASS", "WORKER_HASH_MISMATCH",
    "unify-srv-customer-phones-v1.ps1","customer-unified-phones-v1.status",
    "customers.before-phone-unify-v1.sqlite.bak", "phone-source-newbase-v1.sqlite",
    "119622c532190bb63b46d79150b62ce61d717b53964fdca4e58287ecc24d8736",
    "ac8a3345fa94645a93094590da26d7db3c034150",
    "ALREADY_ATTEMPTED","TRIGGERS_PRESENT","SOURCE_TASK_CONCURRENT",
    "WORKER_PS2_PARSE_FAILED","AUTO_UPDATE=OFF", "ONEC_WRITES=0", "BITRIX_WRITES=0"):
   self.assertIn(needle,s)
  for banned in ("Triggers.Create","DeleteTask(", "Remove-Item", "crm.item.add",
    "crm.item.update", "Set-ScheduledTask", "CreateFileW"):
   self.assertNotIn(banned,s)
  self.assertNotIn("\r",s)
  print("CUSTOMER_PHONE_UNIFY_LAUNCHER_SHA256="+hashlib.sha256(data).hexdigest())
if __name__ == "__main__":unittest.main()

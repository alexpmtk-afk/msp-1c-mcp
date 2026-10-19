"""Keep delivery status honest: CI PASS does not mean real SRV / Bitrix acceptance."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "delivery-gates.json"

class DeliveryGateContract(unittest.TestCase):
    def test_evidence_and_release_claims(self):
        v = json.loads(P.read_text(encoding="utf-8"))
        self.assertEqual(v["version"], 1)
        self.assertEqual(v["source"], "TEST_NEWBASE")
        self.assertIn(v["mode"], ("AUTO_UPDATE_OFF", "AUTO_UPDATE_ON"))
        c = v["checks"]
        names = ("mapped_buyers", "source_phones", "crm_phone_readonly_audit",
                 "crm_phone_one_card_pilot", "crm_phone_bulk_backfill",
                 "name_and_inn_fields", "daily_sync", "unified_local_database")
        self.assertEqual(set(c), set(names))
        b, src, audit = c["mapped_buyers"], c["source_phones"], c["crm_phone_readonly_audit"]
        self.assertEqual(b["target"], b["accepted"])
        self.assertEqual(src["rows"], src["format_candidates"] + src["review_rows"])
        self.assertEqual(src["buyers"], audit["checked"])
        self.assertEqual(audit["checked"], audit["with_phone"] + audit["empty_phone"])
        unified = c["unified_local_database"]
        self.assertEqual(unified["state"], "ACCEPTED_ON_SRV")
        self.assertEqual(unified["buyers"], b["accepted"])
        self.assertEqual(unified["mapped_buyers"], b["accepted"])
        self.assertEqual(unified["buyers_with_name"], unified["buyers"])
        self.assertEqual(unified["buyers_with_inn"], 1925)
        self.assertEqual(unified["phone_rows"], src["rows"])
        self.assertEqual(unified["phone_buyers"], src["buyers"])
        self.assertEqual(unified["phone_candidates"], src["format_candidates"])
        self.assertEqual(unified["phone_review"], src["review_rows"])
        self.assertTrue(unified["original_customer_fields_unmodified"])
        self.assertIn("INN_NAME_DIFFERENCES=0", unified["receipt"])
        self.assertEqual(v["overall"] in ("INCOMPLETE", "ACCEPTED"), True)
        for k in ("crm_phone_one_card_pilot", "crm_phone_bulk_backfill"):
            stage = c[k]
            self.assertIn(stage["state"], ("NOT_DONE", "ACCEPTED"))
            self.assertGreaterEqual(stage["cards_updated"], 0)
            self.assertGreaterEqual(stage["phones_backread_verified"], 0)
            if stage["state"] == "ACCEPTED":
                self.assertIsInstance(stage["receipt"], str)
                self.assertIn("PASS", stage["receipt"])
                self.assertIn("BACKREAD", stage["receipt"])
                self.assertGreater(stage["cards_updated"], 0)
                self.assertGreater(stage["phones_backread_verified"], 0)
            elif stage["state"] == "NOT_DONE":
                self.assertEqual(stage["cards_updated"], 0)
                self.assertEqual(stage["phones_backread_verified"], 0)
        pilot, bulk = c["crm_phone_one_card_pilot"], c["crm_phone_bulk_backfill"]
        if bulk["state"] == "ACCEPTED":
            self.assertEqual(pilot["state"], "ACCEPTED")
            self.assertEqual(bulk["phones_backread_verified"], src["format_candidates"])
            self.assertEqual(bulk["cards_updated"], src["buyers"] - src["review_rows"])
        other = c["name_and_inn_fields"]
        self.assertIn(other["state"], ("NOT_DONE", "ACCEPTED"))
        if other["state"] == "ACCEPTED":
            self.assertTrue(other["reviewed_complete"])
            self.assertIn("PASS", other["receipt"])
        else:
            self.assertFalse(other["reviewed_complete"])
        daily = c["daily_sync"]
        self.assertIn(daily["state"], ("OFF", "ACCEPTED"))
        if daily["state"] == "ACCEPTED":
            self.assertEqual(v["mode"], "AUTO_UPDATE_ON")
            self.assertGreaterEqual(daily["actual_runs"], 1)
            self.assertIn("PASS", daily["receipt"])
        else:
            self.assertEqual(v["mode"], "AUTO_UPDATE_OFF")
        if v["overall"] == "ACCEPTED":
            self.assertTrue(all(c[k]["state"] == "ACCEPTED"
                                for k in ("crm_phone_one_card_pilot", "crm_phone_bulk_backfill",
                                          "name_and_inn_fields", "daily_sync")))
        else:
            self.assertTrue(any(c[k]["state"] != "ACCEPTED"
                                for k in ("crm_phone_one_card_pilot", "crm_phone_bulk_backfill",
                                          "name_and_inn_fields", "daily_sync")))

if __name__ == "__main__":
    unittest.main()

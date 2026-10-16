import importlib.util
from pathlib import Path
import threading
import time
import unittest

spec=importlib.util.spec_from_file_location(
    "relay",Path(__file__).resolve().parent.parent/"bitrix_relay.py")
relay=importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)

class TestRelay(unittest.TestCase):
    def test_reject_excessive_or_control_query(self):
        q=relay.Queue(max_pending=1)
        for term in ("xx","x"*81,"abc\n"):
            with self.assertRaises(ValueError):
                q.new(term,"COMPANY")
        with self.assertRaises(ValueError):
            q.new("Рома","ORG")

    def test_never_expose_more_than_twenty(self):
        q=relay.Queue()
        job=q.new("Рома","COMPANY")
        request=q.next()
        self.assertEqual(request["limit"],20)
        self.assertEqual(request["entityType"],"COMPANY")
        records=[{"id":f"{i:08x}-0000-0000-0000-000000000000","name":"Иван"}
                 for i in range(20)]
        self.assertTrue(q.submit(job["id"],records))
        self.assertEqual(len(q.finish(job,0.01)),20)
        self.assertFalse(q.submit(job["id"],records))

    def test_no_cached_customer_data_after_consumption(self):
        q=relay.Queue()
        job=q.new("Иван","CONTACT")
        request=q.next()
        self.assertIn(request["id"],q.pending)
        self.assertEqual(q.finish(job,0.01),[])
        self.assertNotIn(request["id"],q.pending)
        self.assertFalse(q.submit(request["id"],[]))

    def test_result_payload_validation(self):
        guid="12345678-abcd-abcd-abcd-123456789abc"
        self.assertEqual(relay.safe_items([{"id":guid,"name":"Иванов","inn":"SHOULD_NOT_LEAVE"}]),
                         [{"id":guid,"name":"Иванов"}])
        with self.assertRaises(ValueError):
            relay.safe_items([{"id":"bad","name":"Петров"}])
        with self.assertRaises(ValueError):
            relay.safe_items([{"id":guid,"name":"<script>\n"}])
        with self.assertRaises(ValueError):
            relay.safe_items([{"id":guid,"name":"X"}]*21)

    def test_iframe_escapes_script_injection(self):
        guid="12345678-abcd-abcd-abcd-123456789abc"
        page,csp=relay.iframe_html(
            [{"id":guid,"name":"</script><img src=x onerror=alert(1)>"}],
            "example.bitrix24.ru",
            "https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js")
        self.assertNotIn(b"</script><img",page)
        self.assertIn(b"crmShowFoundEntities",page)
        self.assertIn("frame-ancestors https://example.bitrix24.ru",csp)

    def test_config_needs_pinned_portal_and_loopback(self):
        with self.assertRaises(ValueError):
            relay.RelayServer("0.0.0.0",0,"example.bitrix24.ru","id",
                              "x"*40,"https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js")
        with self.assertRaises(ValueError):
            relay.RelayServer("127.0.0.1",0,"example.bitrix24.ru","id",
                              "short","https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js")
        with self.assertRaises(ValueError):
            relay.RelayServer("127.0.0.1",0,"example.bitrix24.ru","id",
                              "x"*40,"https://evil.example/sdk.js")

if __name__=="__main__":
    unittest.main()

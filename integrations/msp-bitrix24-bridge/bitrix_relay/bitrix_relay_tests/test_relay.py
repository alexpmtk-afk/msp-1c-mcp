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
            relay.RelayServer("0.0.0.0",0,relay.APPROVED_PORTAL,"a"*32,
                              "x"*40,"https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js")
        with self.assertRaises(ValueError):
            relay.RelayServer("127.0.0.1",0,relay.APPROVED_PORTAL,"a"*32,
                              "short","https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js")
        with self.assertRaises(ValueError):
            relay.RelayServer("127.0.0.1",0,relay.APPROVED_PORTAL,"a"*32,
                              "x"*40,"https://evil.example/sdk.js")


    def test_portal_pinning_and_no_guessed_member(self):
        with self.assertRaises(ValueError):
            relay.RelayServer("127.0.0.1",0,"another.bitrix24.ru","a"*32,
                              "x"*40,"https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js")
        with self.assertRaises(ValueError):
            relay.RelayServer("127.0.0.1",0,relay.APPROVED_PORTAL,"unknown",
                              "x"*40,"https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js")
        self.assertEqual(relay.APPROVED_PORTAL,"b24-uwmjda.bitrix24.ru")
        self.assertFalse(relay.is_authenticated_user("another.bitrix24.ru","fake"))

    def test_placement_query_form_contract(self):
        import urllib.request
        import urllib.parse
        import urllib.error
        import json
        import threading
        from time import sleep
        s=relay.RelayServer(
            "127.0.0.1",0,relay.APPROVED_PORTAL,"a"*32,"w"*40,
            "https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js",
            validator=lambda domain,token: domain == relay.APPROVED_PORTAL and token=="synthetic-ok")
        thread=threading.Thread(target=s.serve_forever,daemon=True)
        thread.start()
        try:
            def call(domain,placement,token="synthetic-ok"):
                url=("http://127.0.0.1:%d/bitrix/search?"%s.server_address[1]+
                     urllib.parse.urlencode({"DOMAIN":domain,"PLACEMENT":placement}))
                form={"member_id":"a"*32,"AUTH_ID":token,
                      "PLACEMENT_OPTIONS":json.dumps({"entityTypeName":"COMPANY","searchQuery":"Рома"})}
                return urllib.request.urlopen(urllib.request.Request(
                    url,data=urllib.parse.urlencode(form).encode(),method="POST"),timeout=3)
            for domain,placement in [("bad.bitrix24.ru","CRM_DETAIL_SEARCH"),
                                      (relay.APPROVED_PORTAL,"OTHER")]:
                with self.assertRaises(urllib.error.HTTPError) as error:
                    call(domain,placement)
                self.assertEqual(error.exception.code,403)
            def worker():
                for _ in range(80):
                    job=s.queue.next()
                    if job:
                        s.queue.submit(job["id"],[{"id":"12345678-abcd-abcd-abcd-123456789abc",
                                                   "name":"Тестовая компания"}])
                        return
                    sleep(.02)
                raise AssertionError("worker did not see request")
            w=threading.Thread(target=worker,daemon=True)
            w.start()
            with call(relay.APPROVED_PORTAL,relay.REQUIRED_PLACEMENT) as response:
                self.assertEqual(response.status,200)
                body=response.read().decode()
                self.assertIn("crmShowFoundEntities",body)
                self.assertIn("12345678-abcd-abcd-abcd-123456789abc",body)
                self.assertIn("crmShowFoundEntities",body)
            w.join(2)
            self.assertFalse(s.queue.pending)
        finally:
            s.shutdown()
            s.server_close()
            thread.join(2)

if __name__=="__main__":
    unittest.main()

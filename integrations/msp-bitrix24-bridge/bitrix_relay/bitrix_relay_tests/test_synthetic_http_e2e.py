"""Synthetic HTTP E2E: CRM_DETAIL_SEARCH -> relay -> authorized worker -> iframe.

All records and credentials are synthetic. Bound only to 127.0.0.1 with
ephemeral port; no public Bitrix, VPS, SRV, CRM, or 1C requests.
"""
import importlib.util
import json
from pathlib import Path
import threading
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request


SPEC=importlib.util.spec_from_file_location(
    "bitrix_relay_e2e",
    Path(__file__).resolve().parents[1]/"bitrix_relay.py",
)
relay=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(relay)

PORTAL=relay.APPROVED_PORTAL
MEMBER="a"*32
WORKER_TOKEN="test_worker_token_"+"w"*40
APP_TOKEN="test_application_"+"b"*40
SDK="https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js"
GUID="12345678-abcd-abcd-abcd-123456789abc"


class SyntheticHttpE2E(unittest.TestCase):
    def setUp(self):
        self.server=relay.RelayServer(
            "127.0.0.1",0,PORTAL,MEMBER,WORKER_TOKEN,SDK,
            validator=lambda domain,token: domain==PORTAL and token=="synthetic-auth",
            application_token=APP_TOKEN,
        )
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        self.url="http://127.0.0.1:%d"%self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(3)
        self.assertFalse(self.thread.is_alive())

    def request(self,path,method="GET",payload=None,token=None):
        headers={}
        if token is not None:
            headers["X-Msp-Worker-Token"]=token
        if payload is not None:
            headers["Content-Type"]="application/json"
            payload=json.dumps(payload,ensure_ascii=True).encode("ascii")
        return urllib.request.urlopen(
            urllib.request.Request(self.url+path,data=payload,
                                   headers=headers,method=method),timeout=5,
        )

    def placement(self, query="Тестовая", domain=PORTAL,
                  member=MEMBER, auth="synthetic-auth",
                  application_token=APP_TOKEN, kind="COMPANY"):
        params=urllib.parse.urlencode({"DOMAIN":domain,
                                       "PLACEMENT":relay.REQUIRED_PLACEMENT})
        form={
            "member_id":member,
            "AUTH_ID":auth,
            "APPLICATION_TOKEN":application_token,
            "APPLICATION_SCOPE":"crm,placement,user_basic",
            "PLACEMENT_OPTIONS":json.dumps(
                {"entityTypeName":kind,"searchQuery":query},
                ensure_ascii=False,
            ),
        }
        request=urllib.request.Request(
            self.url+"/bitrix/search?"+params,
            data=urllib.parse.urlencode(form).encode("utf-8"),
            method="POST",
        )
        return urllib.request.urlopen(request,timeout=15)

    def test_worker_endpoint_denies_unauthenticated_and_idle(self):
        for token in (None,"invalid",APP_TOKEN):
            with self.assertRaises(urllib.error.HTTPError) as denial:
                self.request("/worker/next",token=token)
            self.assertEqual(denial.exception.code,404)
        with self.request("/worker/next",token=WORKER_TOKEN) as response:
            self.assertEqual(response.status,204)
            self.assertEqual(response.read(),b"")
        self.assertFalse(self.server.queue.pending)

    def test_reject_invalid_portal_member_app_and_oauth_without_queue(self):
        cases=[
            {"domain":"another.bitrix24.ru"},
            {"member":"b"*32},
            {"application_token":"c"*40},
            {"auth":"expired-synthetic-token"},
            {"query":"ab"},
            {"kind":"LEAD"},
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments):
                with self.assertRaises(urllib.error.HTTPError) as denial:
                    self.placement(**arguments)
                self.assertEqual(denial.exception.code,403)
                self.assertFalse(self.server.queue.pending)

    def test_synthetic_full_http_roundtrip_and_no_retained_customer(self):
        seen=[]
        worker_error=[]
        def worker():
            try:
                deadline=time.monotonic()+8
                while time.monotonic()<deadline:
                    with self.request("/worker/next",token=WORKER_TOKEN) as reply:
                        if reply.status==204:
                            time.sleep(0.02)
                            continue
                        self.assertEqual(reply.status,200)
                        job=json.loads(reply.read().decode("ascii"))
                    self.assertEqual(job["query"],"Тестовая")
                    self.assertEqual(job["entityType"],"COMPANY")
                    self.assertEqual(job["limit"],20)
                    self.assertRegex(job["id"],r"^[0-9a-f]{32}$")
                    seen.append(job["id"])
                    result={
                        "id":job["id"],
                        "items":[{"id":GUID,"name":"Тестовая компания",
                                  "inn":"SYNTHETIC_SHOULD_BE_DROPPED"}],
                    }
                    with self.request("/worker/result",method="POST",
                                      payload=result,token=WORKER_TOKEN) as reply:
                        self.assertEqual(reply.status,204)
                    return
                raise AssertionError("synthetic job was not delivered")
            except Exception as exc:
                worker_error.append(exc)

        t=threading.Thread(target=worker,daemon=True)
        t.start()
        with self.placement() as response:
            self.assertEqual(response.status,200)
            body=response.read().decode("utf-8")
            csp=response.headers["Content-Security-Policy"]
        t.join(5)
        self.assertFalse(t.is_alive())
        if worker_error:
            raise worker_error[0]
        self.assertEqual(len(seen),1)
        self.assertIn("crmShowFoundEntities",body)
        self.assertIn(GUID,body)
        self.assertIn(r"\u0422",body)
        self.assertNotIn("SYNTHETIC_SHOULD_BE_DROPPED",body)
        self.assertIn("frame-ancestors https://"+PORTAL,csp)
        self.assertFalse(self.server.queue.pending)
        with self.assertRaises(urllib.error.HTTPError) as reply:
            self.request("/worker/result",method="POST",token=WORKER_TOKEN,
                         payload={"id":seen[0],"items":[]})
        self.assertEqual(reply.exception.code,409)


if __name__=="__main__":
    unittest.main()

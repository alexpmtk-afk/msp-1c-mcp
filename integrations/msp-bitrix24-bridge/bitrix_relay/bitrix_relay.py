"""Bitrix24 CRM_DETAIL_SEARCH relay, prototype only, fail-closed by default.

No customer database or SQLite backup on this host. Run behind approved
HTTPS reverse proxy, bound on 127.0.0.1, with a portal-domain allowlist.
SRV connects outbound to /worker/*; never expose SRV IIS/SMB/SQLite.
"""
from __future__ import annotations

from collections import deque
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import re
import secrets
import threading
import time
from urllib.parse import parse_qs, urlsplit, urlencode
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.error import HTTPError, URLError


DOMAIN_RE = re.compile(r"^[a-z0-9][a-z0-9.-]{2,190}[a-z0-9]$")
GUID_RE = re.compile(r"^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$")
MAX_SEARCH = 80
MAX_RESULTS = 20
APPROVED_PORTAL = "b24-uwmjda.bitrix24.ru"
REQUIRED_PLACEMENT = "CRM_DETAIL_SEARCH"
REQUIRED_SCOPES = frozenset({"crm", "placement"})
USER_LOOKUP_SCOPES = frozenset({"user", "user_basic", "user_brief"})


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def safe_items(items):
    if not isinstance(items, list) or len(items) > MAX_RESULTS:
        raise ValueError("result list invalid")
    result = []
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("result element invalid")
        guid, name = item.get("id"), item.get("name")
        if (not isinstance(guid, str) or not GUID_RE.fullmatch(guid)
                or not isinstance(name, str) or not 1 <= len(name) <= 256
                or any(ord(ch) < 32 for ch in name)):
            raise ValueError("result fields invalid")
        result.append({"id": guid, "name": name})
    return result


class Queue:
    def __init__(self, max_pending=32):
        self.lock = threading.Lock()
        self.waiting = deque()
        self.pending = {}
        self.max_pending = max_pending

    def new(self, query, kind):
        if kind not in ("COMPANY", "CONTACT") or not 3 <= len(query) <= MAX_SEARCH:
            raise ValueError("query invalid")
        if any(ord(ch) < 32 or ord(ch) == 127 for ch in query):
            raise ValueError("controls")
        with self.lock:
            if len(self.pending) >= self.max_pending:
                raise ValueError("capacity")
            job = {"id": secrets.token_hex(16), "query": query, "kind": kind,
                   "event": threading.Event(), "results": None, "created": time.monotonic()}
            self.pending[job["id"]] = job
            self.waiting.append(job["id"])
            return job

    def next(self):
        with self.lock:
            while self.waiting:
                key = self.waiting.popleft()
                job = self.pending.get(key)
                if job and time.monotonic() - job["created"] < 20:
                    return {"id": key, "query": job["query"],
                            "entityType": job["kind"], "limit": MAX_RESULTS}
            return None

    def submit(self, key, items):
        validated = safe_items(items)
        with self.lock:
            job = self.pending.get(key)
            if not job or job["event"].is_set() or time.monotonic() - job["created"] > 20:
                return False
            job["results"] = validated
            job["event"].set()
            return True

    def finish(self, job, timeout=12):
        job["event"].wait(timeout)
        with self.lock:
            self.pending.pop(job["id"], None)
            return job["results"] if job["results"] is not None else []


def is_authenticated_user(domain, token, timeout=5):
    """Check bearer credentials directly with the *fixed* authorized Bitrix24 host."""
    if domain != APPROVED_PORTAL or not token or len(token) > 512:
        return False
    url = "https://" + domain + "/rest/user.current.json"
    payload = urlencode({"auth": token}).encode("ascii")
    req = Request(url, data=payload, method="POST",
                  headers={"Content-Type": "application/x-www-form-urlencoded",
                           "Accept": "application/json"})
    try:
        with build_opener(NoRedirects).open(req, timeout=timeout) as result:
            parsed = urlsplit(result.geturl())
            if parsed.scheme != "https" or parsed.hostname != APPROVED_PORTAL:
                return False
            if result.status != 200:
                return False
            data = json.loads(result.read(16384))
            value = data.get("result", {})
            return isinstance(value, dict) and str(value.get("ID", "")).isdigit()
    except (HTTPError, URLError, OSError, ValueError, TypeError, json.JSONDecodeError):
        return False



def iframe_html(items, portal, sdk):
    """Only syntactically valid, already authenticated result items reach the iframe."""
    payload = json.dumps({"data": items}, ensure_ascii=True, separators=(",", ":"))
    payload = payload.replace("<", "\\u003c").replace(">", "\\u003e")
    nonce = secrets.token_urlsafe(18)
    page = ('<!doctype html><html lang="ru"><head><meta charset="UTF-8">'
            '<title>Поиск клиентов</title></head><body>'
            '<script src="' + sdk + '"></script>'
            '<script nonce="' + nonce + '">'
            'document.addEventListener("DOMContentLoaded",async function(){'
            'try{const app=await B24Js.initializeB24Frame();'
            'await app.placement.call("crmShowFoundEntities",' + payload + ');'
            '}catch(e){document.body.textContent="Поиск временно недоступен";}'
            '});</script></body></html>')
    csp = ("default-src 'none'; script-src 'nonce-" + nonce +
           "' " + sdk.split("/")[0] + "//" + urlsplit(sdk).hostname +
           "; frame-ancestors https://" + portal +
           "; base-uri 'none'; form-action 'none'")
    return page.encode("utf-8"), csp


class Handler(BaseHTTPRequestHandler):
    server_version = "MspBitrixReadOnly/0.1"
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        return  # Never log searches, access tokens, names or identifiers.

    def reply(self, status, payload=b"", mime="application/json", extra=None):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.close_connection = True
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(payload)

    def authenticated_worker(self):
        incoming = self.headers.get("X-Msp-Worker-Token", "")
        secret = self.server.worker_token
        return 32 <= len(incoming) <= 256 and hmac.compare_digest(incoming, secret)

    def read_body(self, max_bytes):
        raw_size = self.headers.get("Content-Length", "0")
        if not raw_size.isdecimal() or not 1 <= int(raw_size) <= max_bytes:
            raise ValueError("invalid content length")
        return self.rfile.read(int(raw_size))

    def do_GET(self):
        path = urlsplit(self.path).path
        if path != "/worker/next" or not self.authenticated_worker():
            self.reply(404)
            return
        job = self.server.queue.next()
        if job is None:
            self.reply(204)
        else:
            self.reply(200, json.dumps(job, ensure_ascii=True).encode("ascii"))

    def do_POST(self):
        path = urlsplit(self.path).path
        if path == "/worker/result":
            if not self.authenticated_worker():
                self.reply(404)
                return
            try:
                payload = json.loads(self.read_body(16384))
                if not isinstance(payload, dict):
                    raise ValueError()
                key = payload.get("id")
                if not isinstance(key, str) or not re.fullmatch(r"[0-9a-f]{32}", key):
                    raise ValueError()
                success = self.server.queue.submit(key, payload.get("items"))
            except (ValueError, UnicodeError, TypeError):
                self.reply(400)
                return
            self.reply(204 if success else 409)
            return
        if path != "/bitrix/search":
            self.reply(404)
            return
        try:
            content = self.read_body(16384).decode("utf-8", errors="strict")
            args = parse_qs(content, max_num_fields=30)
            opts = json.loads(args.get("PLACEMENT_OPTIONS", [""])[0])
            if not isinstance(opts, dict):
                raise ValueError()
            kind = opts.get("entityTypeName")
            term = opts.get("searchQuery")
            if not isinstance(term, str) or kind not in ("COMPANY", "CONTACT"):
                raise ValueError()
            if (not 3 <= len(term.strip()) <= MAX_SEARCH
                    or any(ord(ch) < 32 or ord(ch) == 127 for ch in term)):
                raise ValueError()
            params = parse_qs(urlsplit(self.path).query)
            domain = params.get("DOMAIN", [""])[0].lower()
            if domain != self.server.portal:
                raise ValueError()
            if args.get("member_id", [""])[0] != self.server.member_id:
                raise ValueError()
            placement_query = params.get("PLACEMENT", [])
            placement_body = args.get("PLACEMENT", [])
            if (len(placement_query) > 1 or len(placement_body) > 1 or
                    (placement_query and placement_body and
                     placement_query[0] != placement_body[0])):
                raise ValueError()
            placement = placement_query[0] if placement_query else (placement_body[0] if placement_body else "")
            if placement != REQUIRED_PLACEMENT:
                raise ValueError()
            scope_values = args.get("APPLICATION_SCOPE", [])
            if len(scope_values) != 1:
                raise ValueError()
            scopes = {part.strip().lower() for part in scope_values[0].split(",")}
            if not REQUIRED_SCOPES.issubset(scopes) or not scopes.intersection(USER_LOOKUP_SCOPES):
                raise ValueError()
            auth = args.get("AUTH_ID", [""])[0]
            if not self.server.validator(domain, auth):
                raise ValueError()
            job = self.server.queue.new(term.strip(), kind)
            items = self.server.queue.finish(job)
            body, csp = iframe_html(items, self.server.portal, self.server.sdk)
            self.reply(200, body, "text/html; charset=utf-8",
                       {"Content-Security-Policy": csp})
        except (ValueError, UnicodeError, TypeError, json.JSONDecodeError):
            self.reply(403)


class RelayServer(ThreadingHTTPServer):
    def __init__(self, host, port, portal, member_id, worker_token, sdk,
                 validator=is_authenticated_user):
        if portal != APPROVED_PORTAL or not re.fullmatch(r"[a-f0-9]{32}", member_id):
            raise ValueError("portal/member config invalid")
        if len(worker_token) < 32 or len(worker_token) > 256:
            raise ValueError("worker secret too short")
        if not sdk.startswith("https://unpkg.com/@bitrix24/b24jssdk@1/"):
            raise ValueError("SDK URL outside allowlist")
        if host != "127.0.0.1":
            raise ValueError("relay may only bind loopback")
        self.portal = portal
        self.member_id = member_id
        self.worker_token = worker_token
        self.sdk = sdk
        self.validator = validator
        self.queue = Queue()
        super().__init__((host, port), Handler)


if __name__ == "__main__":
    portal = APPROVED_PORTAL
    member_id = os.environ["MSP_B24_MEMBER_ID"]
    token = os.environ["MSP_B24_WORKER_TOKEN"]
    sdk = "https://unpkg.com/@bitrix24/b24jssdk@1/dist/umd/index.min.js"
    srv = RelayServer("127.0.0.1", int(os.environ.get("MSP_B24_RELAY_PORT", "9814")),
                      portal, member_id, token, sdk)
    srv.serve_forever()

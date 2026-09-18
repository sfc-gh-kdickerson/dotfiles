#!/usr/bin/env python3
"""CWS-side MCP facade. Stays up when the Mac tunnel dies."""

from __future__ import print_function

import json
import os
import sys
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from lock import open_and_lock, read_lock_pid, state_dir
from protocol import (
    FACADE_PORT,
    HOST_URL,
    OFFLINE_MESSAGE,
    bearer_ok,
    daemonize,
    encode_sse,
    eprint,
    handle_mcp_request,
    mcp_text_result,
    read_body,
    read_token,
    wants_sse,
    write_json,
)
from tools import TOOLS

LOCK_NAME = "facade.lock"
_LOCK_FD = None
_LAST_HOST_ERROR = "never reached"


def host_headers(token):
    return {"Authorization": "Bearer %s" % token, "Content-Type": "application/json"}


def host_health(token, timeout=1.5):
    global _LAST_HOST_ERROR
    req = Request(HOST_URL + "/health", headers=host_headers(token), method="GET")
    try:
        with urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        if payload.get("ok"):
            _LAST_HOST_ERROR = ""
            return True
        _LAST_HOST_ERROR = "host /health returned %s" % payload
        return False
    except Exception as exc:
        _LAST_HOST_ERROR = str(exc)
        return False


def host_call(token, name, arguments, timeout=600):
    body = json.dumps({"name": name, "arguments": arguments or {}}).encode("utf-8")
    req = Request(HOST_URL + "/call", data=body, headers=host_headers(token), method="POST")
    try:
        with urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        raise RuntimeError("host HTTP %s: %s" % (exc.code, raw))
    except URLError as exc:
        raise ConnectionError(str(exc.reason or exc))
    if not payload.get("ok"):
        raise RuntimeError(payload.get("error") or "host call failed")
    return payload.get("result")


def call_tool(token, name, arguments):
    if name == "host_status":
        up = host_health(token)
        return mcp_text_result(
            json.dumps(
                {
                    "connected": up,
                    "last_error": _LAST_HOST_ERROR or None,
                    "reconnect": "On your Mac: connect <workspace_id>   (sf ws ls)",
                    "host": HOST_URL,
                },
                indent=2,
            )
        )
    if not host_health(token):
        return mcp_text_result(OFFLINE_MESSAGE, is_error=True)
    try:
        result = host_call(token, name, arguments)
    except ConnectionError:
        return mcp_text_result(OFFLINE_MESSAGE, is_error=True)
    except Exception as exc:
        return mcp_text_result(str(exc), is_error=True)
    if isinstance(result, str):
        return mcp_text_result(result)
    return mcp_text_result(json.dumps(result, indent=2, default=str))


class FacadeHandler(BaseHTTPRequestHandler):
    token = ""

    def log_message(self, fmt, *args):
        eprint("[facade]", fmt % args)

    def _auth(self):
        # Cursor may omit auth on initialize; still require it for HTTP clients
        # that send the header. Token-less local loopback is accepted only if
        # the configured token matches when a header is present.
        header = self.headers.get("Authorization")
        if header and not bearer_ok(header, self.token):
            write_json(self, 401, {"error": "unauthorized"})
            return False
        return True

    def do_GET(self):
        if self.path in ("/health", "/"):
            write_json(
                self,
                200,
                {
                    "ok": True,
                    "pid": os.getpid(),
                    "host_connected": host_health(self.token),
                    "last_error": _LAST_HOST_ERROR or None,
                },
            )
            return
        if self.path.rstrip("/") == "/mcp":
            self.send_response(405)
            self.send_header("Allow", "POST")
            self.end_headers()
            return
        write_json(self, 404, {"error": "not found"})

    def do_POST(self):
        if self.path.rstrip("/") != "/mcp":
            write_json(self, 404, {"error": "not found"})
            return
        if not self._auth():
            return
        raw = read_body(self)
        try:
            message = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            write_json(self, 400, {"error": "invalid json"})
            return

        session = self.headers.get("Mcp-Session-Id") or str(uuid.uuid4())
        extra = [("Mcp-Session-Id", session)]

        def _call(name, arguments):
            return call_tool(self.token, name, arguments)

        if isinstance(message, list):
            responses = [handle_mcp_request(item, TOOLS, _call) for item in message]
            responses = [r for r in responses if r is not None]
            payload = responses
        else:
            payload = handle_mcp_request(message, TOOLS, _call)

        if payload is None:
            self.send_response(202)
            self.send_header("Mcp-Session-Id", session)
            self.end_headers()
            return

        if wants_sse(self.headers.get("Accept")):
            body = encode_sse(payload)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Mcp-Session-Id", session)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        write_json(self, 200, payload, extra_headers=extra)


def stdio_loop(token):
    def _call(name, arguments):
        return call_tool(token, name, arguments)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": str(exc)}}) + "\n")
            sys.stdout.flush()
            continue
        payload = handle_mcp_request(message, TOOLS, _call)
        if payload is not None:
            sys.stdout.write(json.dumps(payload) + "\n")
            sys.stdout.flush()


def serve(token):
    FacadeHandler.token = token
    httpd = ThreadingHTTPServer(("127.0.0.1", FACADE_PORT), FacadeHandler)
    eprint("facade listening on 127.0.0.1:%d" % FACADE_PORT)
    httpd.serve_forever()


def main(argv):
    log_path = os.path.join(state_dir(), "facade.log")
    daemon = False
    stdio = False
    i = 1
    while i < len(argv):
        if argv[i] == "--daemon":
            daemon = True
        elif argv[i] == "--stdio":
            stdio = True
        elif argv[i] == "--log":
            i += 1
            log_path = argv[i]
        else:
            eprint("unknown arg: %s" % argv[i])
            sys.exit(2)
        i += 1

    token = read_token()
    if not token:
        eprint("missing token in %s" % os.path.join(state_dir(), "token"))
        sys.exit(1)

    if stdio:
        stdio_loop(token)
        return

    if daemon:
        daemonize(log_path)

    global _LOCK_FD
    lock_path = os.path.join(state_dir(), LOCK_NAME)
    _LOCK_FD = open_and_lock(lock_path)
    if _LOCK_FD is None:
        eprint("facade already running pid=%s" % read_lock_pid(lock_path))
        sys.exit(0)
    serve(token)


if __name__ == "__main__":
    main(sys.argv)

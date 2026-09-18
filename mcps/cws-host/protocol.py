"""JSON-RPC / MCP helpers and shared HTTP bits. Stdlib only, py3.9+."""

from __future__ import print_function

import json
import os
import secrets
import sys

import hashlib

from lock import state_dir

TREE_FILES = ("host.py", "facade.py", "protocol.py", "tools.py", "lock.py", "lockrun.py")


def tree_hash(root):
    digest = hashlib.sha256()
    for name in TREE_FILES:
        path = os.path.join(root, name)
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        with open(path, "rb") as fh:
            digest.update(fh.read())
        digest.update(b"\0")
    return digest.hexdigest()

PROTOCOL_VERSION = "2025-03-26"
SERVER_NAME = "mac-host"
SERVER_VERSION = "0.1.0"
HOST_PORT = 18766
FACADE_PORT = 18765
HOST_URL = "http://127.0.0.1:%d" % HOST_PORT

OFFLINE_MESSAGE = (
    "Mac host is not connected. The reverse tunnel is down. "
    "On your laptop run: connect <workspace_id>   (id from `sf ws ls`)"
)


def read_token():
    path = os.path.join(state_dir(), "token")
    try:
        with open(path, "r") as fh:
            token = fh.read().strip()
    except OSError:
        return None
    return token or None


def ensure_token():
    path = os.path.join(state_dir(), "token")
    token = read_token()
    if token:
        return token
    token = secrets.token_hex(32)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(token + "\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    return token


def bearer_ok(header_value, token):
    if not token or not header_value:
        return False
    prefix = "Bearer "
    if not header_value.startswith(prefix):
        return False
    return header_value[len(prefix) :].strip() == token


def json_rpc_result(req_id, result):
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def json_rpc_error(req_id, code, message):
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": code, "message": message},
    }


def mcp_text_result(text, is_error=False):
    payload = {"content": [{"type": "text", "text": text}]}
    if is_error:
        payload["isError"] = True
    return payload


def mcp_initialize_result():
    return {
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {"tools": {"listChanged": False}},
        "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
    }


def handle_mcp_request(message, tools, call_tool):
    """Dispatch one JSON-RPC MCP message. Returns a response dict or None."""
    if not isinstance(message, dict):
        return json_rpc_error(None, -32600, "invalid request")
    method = message.get("method")
    req_id = message.get("id")
    params = message.get("params") or {}

    if method is None:
        return json_rpc_error(req_id, -32600, "missing method")

    # Notifications have no id and get no response.
    is_notification = "id" not in message

    if method == "initialize":
        return json_rpc_result(req_id, mcp_initialize_result())
    if method == "notifications/initialized":
        return None
    if method == "ping":
        if is_notification:
            return None
        return json_rpc_result(req_id, {})
    if method == "tools/list":
        return json_rpc_result(req_id, {"tools": tools})
    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments") or {}
        try:
            result = call_tool(name, arguments)
        except Exception as exc:
            result = mcp_text_result("%s: %s" % (type(exc).__name__, exc), is_error=True)
        return json_rpc_result(req_id, result)

    if is_notification:
        return None
    return json_rpc_error(req_id, -32601, "method not found: %s" % method)


def encode_sse(payload):
    return ("event: message\ndata: %s\n\n" % json.dumps(payload)).encode("utf-8")


def wants_sse(accept_header):
    if not accept_header:
        return False
    return "text/event-stream" in accept_header and "application/json" not in accept_header


def write_json(handler, status, payload, extra_headers=None):
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    if extra_headers:
        for key, value in extra_headers:
            handler.send_header(key, value)
    handler.end_headers()
    handler.wfile.write(body)


def read_body(handler):
    length = int(handler.headers.get("Content-Length") or "0")
    if length <= 0:
        return b""
    return handler.rfile.read(length)


def daemonize(log_path):
    if os.fork() > 0:
        os._exit(0)
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    os.chdir("/")
    os.umask(0o022)
    log_path = os.path.abspath(log_path)
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    log_fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    os.dup2(log_fd, 1)
    os.dup2(log_fd, 2)
    devnull = os.open(os.devnull, os.O_RDONLY)
    os.dup2(devnull, 0)
    if log_fd > 2:
        os.close(log_fd)
    if devnull > 2:
        os.close(devnull)


def eprint(*args):
    print(*args, file=sys.stderr)


def upsert_mac_host_mcp(mcp_path, url, token):
    """Merge mac-host into a Cursor user-level mcp.json. Leave other servers alone."""
    os.makedirs(os.path.dirname(mcp_path), exist_ok=True)
    data = {}
    if os.path.exists(mcp_path):
        with open(mcp_path, "r") as fh:
            raw = fh.read().strip()
        if raw:
            data = json.loads(raw)
    if not isinstance(data, dict):
        data = {}
    servers = data.get("mcpServers")
    if not isinstance(servers, dict):
        servers = {}
    servers["mac-host"] = {
        "url": url,
        "headers": {"Authorization": "Bearer %s" % token},
    }
    data["mcpServers"] = servers
    tmp = mcp_path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, mcp_path)
    return mcp_path


def _cli(argv):
    if len(argv) >= 2 and argv[1] == "upsert-mcp":
        token = read_token()
        if not token:
            eprint("missing token")
            sys.exit(1)
        path = upsert_mac_host_mcp(
            os.path.expanduser("~/.cursor/mcp.json"),
            "http://127.0.0.1:%d/mcp" % FACADE_PORT,
            token,
        )
        print(path)
        return
    eprint("usage: protocol.py upsert-mcp")
    sys.exit(2)


if __name__ == "__main__":
    _cli(sys.argv)

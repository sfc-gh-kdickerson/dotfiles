#!/usr/bin/env python3
"""Mac-side JSON API. Bound to 127.0.0.1; reverse-tunneled to the CWS."""

from __future__ import print_function

import json
import os
import shlex
import shutil
import socket
import stat as statmod
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

from lock import open_and_lock, read_lock_pid, state_dir
from protocol import (
    HOST_PORT,
    bearer_ok,
    daemonize,
    eprint,
    read_body,
    read_token,
    write_json,
)
from tools import HOST_TOOLS, HOST_TOOL_NAMES

INBOX_NAME = "CWS-inbox"
OUTBOX_NAME = "CWS-outbox"
CHROME = "Google Chrome"
LOCK_NAME = "host.lock"
AUDIT_NAME = "audit.log"
WORKSPACE_FILE = "workspace"
_LOCK_FD = None


class ToolError(Exception):
    pass


def inbox_dir():
    path = os.path.join(os.path.expanduser("~"), INBOX_NAME)
    os.makedirs(path, exist_ok=True)
    return path


def outbox_dir():
    path = os.path.join(os.path.expanduser("~"), OUTBOX_NAME)
    os.makedirs(path, exist_ok=True)
    return path


def audit(name, arguments, ok, detail=""):
    line = "%s\t%s\tok=%s\t%s\t%s\n" % (
        datetime.now(timezone.utc).isoformat(),
        name,
        ok,
        json.dumps(arguments, sort_keys=True, default=str),
        detail.replace("\n", " ")[:500],
    )
    path = os.path.join(state_dir(), AUDIT_NAME)
    with open(path, "a") as fh:
        fh.write(line)


def expand_local(path):
    if not path:
        raise ToolError("path is required")
    return os.path.abspath(os.path.expanduser(path))


def persisted_workspace():
    path = os.path.join(state_dir(), WORKSPACE_FILE)
    try:
        with open(path, "r") as fh:
            value = fh.read().strip()
    except OSError:
        value = ""
    return value or os.environ.get("CWS_HOST_WORKSPACE_ID") or ""


def resolve_workspace(explicit):
    workspace = (explicit or persisted_workspace() or "").strip()
    if not workspace:
        raise ToolError("no workspace_id; pass it or run connect <id> first")
    return workspace


def run(cmd, timeout=60, input_bytes=None):
    return subprocess.run(
        cmd,
        input=input_bytes,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def sf_ssh(workspace_id, remote_command, timeout=600, input_bytes=None):
    cmd = ["sf", "ws", "ssh", workspace_id, "--command", remote_command]
    return run(cmd, timeout=timeout, input_bytes=input_bytes)


def chrome_present():
    app = "/Applications/Google Chrome.app"
    return os.path.isdir(app)


def tool_host_info(_args):
    return {
        "home": os.path.expanduser("~"),
        "hostname": socket.gethostname(),
        "chrome": chrome_present(),
        "inbox": inbox_dir(),
        "outbox": outbox_dir(),
        "workspace_id": persisted_workspace() or None,
    }


def tool_open_url(args):
    url = args.get("url") or ""
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ToolError("only https URLs are allowed")
    proc = run(["open", "-a", CHROME, "--", url])
    if proc.returncode != 0:
        raise ToolError((proc.stderr or proc.stdout).decode("utf-8", "replace") or "open failed")
    return {"opened": url}


def tool_open_path(args):
    path = expand_local(args.get("path"))
    if not os.path.exists(path):
        raise ToolError("no such path: %s" % path)
    proc = run(["open", path])
    if proc.returncode != 0:
        raise ToolError((proc.stderr or proc.stdout).decode("utf-8", "replace") or "open failed")
    return {"opened": path}


def tool_reveal_in_finder(args):
    path = expand_local(args.get("path"))
    if not os.path.exists(path):
        raise ToolError("no such path: %s" % path)
    proc = run(["open", "-R", path])
    if proc.returncode != 0:
        raise ToolError((proc.stderr or proc.stdout).decode("utf-8", "replace") or "open failed")
    return {"revealed": path}


def tool_notify(args):
    message = args.get("message") or ""
    if not message:
        raise ToolError("message is required")
    title = args.get("title") or "CWS host"
    script = 'display notification %s with title %s' % (
        json.dumps(message),
        json.dumps(title),
    )
    proc = run(["osascript", "-e", script])
    if proc.returncode != 0:
        raise ToolError((proc.stderr or b"").decode("utf-8", "replace") or "osascript failed")
    return {"notified": True}


def tool_stat(args):
    path = expand_local(args.get("path"))
    try:
        info = os.lstat(path)
    except OSError as exc:
        raise ToolError(str(exc))
    kind = "other"
    if statmod.S_ISDIR(info.st_mode):
        kind = "dir"
    elif statmod.S_ISREG(info.st_mode):
        kind = "file"
    elif statmod.S_ISLNK(info.st_mode):
        kind = "symlink"
    return {
        "path": path,
        "type": kind,
        "size": info.st_size,
        "mtime": int(info.st_mtime),
        "mode": oct(info.st_mode & 0o777),
    }


def tool_listdir(args):
    path = expand_local(args.get("path"))
    try:
        names = sorted(os.listdir(path))
    except OSError as exc:
        raise ToolError(str(exc))
    entries = []
    for name in names:
        full = os.path.join(path, name)
        try:
            info = os.lstat(full)
            is_dir = statmod.S_ISDIR(info.st_mode)
            size = info.st_size
        except OSError:
            is_dir = False
            size = None
        entries.append({"name": name, "dir": is_dir, "size": size})
    return {"path": path, "entries": entries}


def _forbidden_delete(path):
    real = os.path.realpath(path)
    home = os.path.realpath(os.path.expanduser("~"))
    if real in ("/", home):
        return True
    return False


def _expand_remote_home(workspace_id, remote_path):
    if not remote_path.startswith("~/") and not remote_path.startswith("$HOME/"):
        return remote_path
    proc = sf_ssh(workspace_id, 'printf %s "$HOME"', timeout=30)
    home = (proc.stdout or b"").decode("utf-8", "replace").strip()
    if proc.returncode != 0 or not home:
        raise ToolError("could not resolve remote HOME")
    if remote_path.startswith("~/"):
        return home + remote_path[1:]
    return home + remote_path[len("$HOME") :]


def _remote_kind(workspace_id, remote_path):
    quoted = shlex.quote(remote_path)
    script = "if [ ! -e %s ]; then echo MISSING; elif [ -d %s ]; then echo DIR; else echo FILE; fi" % (
        quoted,
        quoted,
    )
    proc = sf_ssh(workspace_id, script, timeout=60)
    text = (proc.stdout or b"").decode("utf-8", "replace").strip().splitlines()
    kind = text[-1] if text else ""
    if proc.returncode != 0 or kind not in ("MISSING", "DIR", "FILE"):
        err = (proc.stderr or proc.stdout).decode("utf-8", "replace")
        raise ToolError("workspace probe failed: %s" % err.strip())
    return kind


def tool_pull_from_cws(args):
    workspace_id = resolve_workspace(args.get("workspace_id"))
    remote_path = args.get("remote_path") or ""
    if not remote_path:
        raise ToolError("remote_path is required")
    remote_path = _expand_remote_home(workspace_id, remote_path)
    local_path = args.get("local_path")
    if local_path:
        dest = expand_local(local_path)
    else:
        dest = os.path.join(inbox_dir(), os.path.basename(remote_path.rstrip("/")))
    delete_source = bool(args.get("delete_source"))

    kind = _remote_kind(workspace_id, remote_path)
    if kind == "MISSING":
        raise ToolError("remote path does not exist: %s" % remote_path)

    parent = os.path.dirname(remote_path.rstrip("/")) or "."
    base = os.path.basename(remote_path.rstrip("/"))
    script = "tar -C %s -cf - %s" % (shlex.quote(parent), shlex.quote(base))
    proc = sf_ssh(workspace_id, script, timeout=600)
    if proc.returncode != 0:
        raise ToolError((proc.stderr or proc.stdout).decode("utf-8", "replace") or "remote tar failed")

    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="cws-pull-")
    try:
        extract = run(["tar", "-C", tmp, "-xf", "-"], input_bytes=proc.stdout, timeout=600)
        if extract.returncode != 0:
            raise ToolError((extract.stderr or b"").decode("utf-8", "replace") or "local tar failed")
        extracted = os.path.join(tmp, base)
        if not os.path.exists(extracted):
            raise ToolError("tar did not produce %s" % base)
        if os.path.exists(dest):
            if os.path.isdir(dest) and not os.path.islink(dest):
                shutil.rmtree(dest)
            else:
                os.remove(dest)
        shutil.move(extracted, dest)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if delete_source:
        rm = sf_ssh(
            workspace_id,
            "rm -rf -- %s" % shlex.quote(remote_path),
            timeout=120,
        )
        if rm.returncode != 0:
            raise ToolError("copied but failed to delete source: %s" % (rm.stderr or b"").decode("utf-8", "replace"))
    return {"local_path": dest, "remote_path": remote_path, "deleted_source": delete_source}


def tool_push_to_cws(args):
    workspace_id = resolve_workspace(args.get("workspace_id"))
    local_path = expand_local(args.get("local_path"))
    if not os.path.exists(local_path):
        raise ToolError("no such local path: %s" % local_path)
    remote_path = args.get("remote_path")
    base = os.path.basename(local_path.rstrip("/"))
    if not remote_path:
        remote_path = "$HOME/%s/%s" % (OUTBOX_NAME, base)
    remote_path = _expand_remote_home(workspace_id, remote_path)
    delete_source = bool(args.get("delete_source"))
    if delete_source and _forbidden_delete(local_path):
        raise ToolError("refusing to delete %s" % local_path)

    parent = os.path.dirname(local_path)
    remote_parent = os.path.dirname(remote_path.rstrip("/")) or "."
    remote_base = os.path.basename(remote_path.rstrip("/"))
    packed = run(["tar", "-C", parent, "-cf", "-", os.path.basename(local_path)], timeout=600)
    if packed.returncode != 0:
        raise ToolError((packed.stderr or b"").decode("utf-8", "replace") or "local tar failed")

    script = "mkdir -p %s && tar -C %s -xf -" % (
        shlex.quote(remote_parent),
        shlex.quote(remote_parent),
    )
    proc = sf_ssh(workspace_id, script, timeout=600, input_bytes=packed.stdout)
    if proc.returncode != 0:
        raise ToolError((proc.stderr or proc.stdout).decode("utf-8", "replace") or "remote tar failed")

    extracted = os.path.join(remote_parent, os.path.basename(local_path))
    if remote_base != os.path.basename(local_path):
        rename = sf_ssh(
            workspace_id,
            "rm -rf -- %s && mv -- %s %s"
            % (shlex.quote(remote_path), shlex.quote(extracted), shlex.quote(remote_path)),
            timeout=60,
        )
        if rename.returncode != 0:
            raise ToolError((rename.stderr or b"").decode("utf-8", "replace") or "remote rename failed")

    if delete_source:
        if os.path.isdir(local_path) and not os.path.islink(local_path):
            shutil.rmtree(local_path)
        else:
            os.remove(local_path)
    return {"local_path": local_path, "remote_path": remote_path, "deleted_source": delete_source}


def tool_clipboard_get(_args):
    proc = run(["pbpaste"])
    if proc.returncode != 0:
        raise ToolError((proc.stderr or b"").decode("utf-8", "replace") or "pbpaste failed")
    return {"text": proc.stdout.decode("utf-8", "replace")}


def tool_clipboard_set(args):
    text = args.get("text")
    if text is None:
        raise ToolError("text is required")
    proc = run(["pbcopy"], input_bytes=text.encode("utf-8"))
    if proc.returncode != 0:
        raise ToolError((proc.stderr or b"").decode("utf-8", "replace") or "pbcopy failed")
    return {"set": True, "bytes": len(text)}


HANDLERS = {
    "host_info": tool_host_info,
    "open_url": tool_open_url,
    "open_path": tool_open_path,
    "reveal_in_finder": tool_reveal_in_finder,
    "notify": tool_notify,
    "stat": tool_stat,
    "listdir": tool_listdir,
    "pull_from_cws": tool_pull_from_cws,
    "push_to_cws": tool_push_to_cws,
    "clipboard_get": tool_clipboard_get,
    "clipboard_set": tool_clipboard_set,
}


def dispatch(name, arguments):
    if name not in HANDLERS:
        raise ToolError("unknown tool: %s" % name)
    return HANDLERS[name](arguments or {})


class HostHandler(BaseHTTPRequestHandler):
    token = ""

    def log_message(self, fmt, *args):
        eprint("[host]", fmt % args)

    def _auth(self):
        if bearer_ok(self.headers.get("Authorization"), self.token):
            return True
        write_json(self, 401, {"error": "unauthorized"})
        return False

    def do_GET(self):
        if not self._auth():
            return
        if self.path == "/health":
            write_json(self, 200, {"ok": True, "pid": os.getpid()})
            return
        if self.path == "/tools":
            write_json(self, 200, {"tools": HOST_TOOLS})
            return
        write_json(self, 404, {"error": "not found"})

    def do_POST(self):
        if not self._auth():
            return
        if self.path != "/call":
            write_json(self, 404, {"error": "not found"})
            return
        try:
            payload = json.loads(read_body(self).decode("utf-8") or "{}")
        except json.JSONDecodeError:
            write_json(self, 400, {"error": "invalid json"})
            return
        name = payload.get("name")
        arguments = payload.get("arguments") or {}
        if name not in HOST_TOOL_NAMES:
            write_json(self, 400, {"error": "unknown tool: %s" % name})
            return
        try:
            result = dispatch(name, arguments)
        except ToolError as exc:
            audit(name, arguments, False, str(exc))
            write_json(self, 200, {"ok": False, "error": str(exc)})
            return
        except Exception as exc:
            audit(name, arguments, False, repr(exc))
            write_json(self, 500, {"ok": False, "error": "%s: %s" % (type(exc).__name__, exc)})
            return
        audit(name, arguments, True)
        write_json(self, 200, {"ok": True, "result": result})


def health_ok(token):
    try:
        with socket.create_connection(("127.0.0.1", HOST_PORT), timeout=0.4) as sock:
            req = (
                "GET /health HTTP/1.1\r\n"
                "Host: 127.0.0.1\r\n"
                "Authorization: Bearer %s\r\n"
                "Connection: close\r\n\r\n" % token
            )
            sock.sendall(req.encode("ascii"))
            data = sock.recv(1024)
        return b" 200 " in data.split(b"\r\n", 1)[0] or data.startswith(b"HTTP/1.0 200") or data.startswith(b"HTTP/1.1 200")
    except OSError:
        return False


def serve():
    token = read_token()
    if not token:
        eprint("missing token in %s" % os.path.join(state_dir(), "token"))
        sys.exit(1)
    HostHandler.token = token
    httpd = ThreadingHTTPServer(("127.0.0.1", HOST_PORT), HostHandler)
    eprint("host listening on 127.0.0.1:%d" % HOST_PORT)
    httpd.serve_forever()


def main(argv):
    log_path = os.path.join(state_dir(), "host.log")
    daemon = False
    i = 1
    while i < len(argv):
        if argv[i] == "--daemon":
            daemon = True
        elif argv[i] == "--log":
            i += 1
            log_path = argv[i]
        else:
            eprint("unknown arg: %s" % argv[i])
            sys.exit(2)
        i += 1

    token = read_token()
    if not token:
        eprint("missing token; run connect first")
        sys.exit(1)

    if daemon:
        daemonize(log_path)

    global _LOCK_FD
    lock_path = os.path.join(state_dir(), LOCK_NAME)
    _LOCK_FD = open_and_lock(lock_path)
    if _LOCK_FD is None:
        if health_ok(token):
            eprint("host already healthy pid=%s" % read_lock_pid(lock_path))
            sys.exit(0)
        pid = read_lock_pid(lock_path)
        eprint("host lock held by pid=%s but /health failed" % pid)
        sys.exit(1)
    serve()


if __name__ == "__main__":
    main(sys.argv)

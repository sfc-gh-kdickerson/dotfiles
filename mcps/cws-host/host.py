#!/usr/bin/env python3
"""Mac-side JSON API. Bound to 127.0.0.1; reverse-tunneled to the CWS."""

from __future__ import print_function

import base64
import hashlib
import json
import os
import shlex
import shutil
import socket
import stat as statmod
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

import chrome as chrome_control
import mac_ui
from lock import open_and_lock, read_lock_pid, state_dir
from protocol import (
    HOST_PORT,
    bearer_ok,
    daemonize,
    eprint,
    read_body,
    read_token,
    write_bytes,
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
CAPTURES = mac_ui.CaptureRegistry()
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
PNG_MAX = 20 * 1024 * 1024
SCRIPT_MAX = 100000
SCRIPT_OUTPUT_MAX = 1024 * 1024
CHROME_INLINE_MAX = 512 * 1024
_IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".tif", ".tiff", ".heic")
_WINDOW_LIST_JXA = r"""
ObjC.import("CoreGraphics");
ObjC.import("Foundation");

function getValue(entry, key) {
    var value = entry.objectForKey(key);
    if (!value) {
        return null;
    }
    return ObjC.deepUnwrap(value);
}

function run() {
    var raw = $.CGWindowListCopyWindowInfo(17, 0);
    var count = $.CFArrayGetCount(raw);
    var windows = [];
    for (var i = 0; i < count; i++) {
        var entry = ObjC.castRefToObject($.CFArrayGetValueAtIndex(raw, i));
        var layer = Number(getValue(entry, "kCGWindowLayer"));
        var onscreen = Boolean(getValue(entry, "kCGWindowIsOnscreen"));
        var bounds = getValue(entry, "kCGWindowBounds") || {};
        var width = Number(bounds.Width || 0);
        var height = Number(bounds.Height || 0);
        var title = String(getValue(entry, "kCGWindowName") || "");
        if (layer !== 0 || !onscreen || !title || width <= 0 || height <= 0) {
            continue;
        }
        windows.push({
            window_id: Number(getValue(entry, "kCGWindowNumber")),
            app: String(getValue(entry, "kCGWindowOwnerName") || ""),
            title: title,
            pid: Number(getValue(entry, "kCGWindowOwnerPID")),
            bounds: {
                x: Number(bounds.X || 0),
                y: Number(bounds.Y || 0),
                width: width,
                height: height
            }
        });
    }
    return JSON.stringify(windows);
}
"""
_OCR_JXA = r"""
ObjC.import("Foundation");
ObjC.import("Vision");

function run(argv) {
    var url = $.NSURL.fileURLWithPath(argv[0]);
    var request = $.VNRecognizeTextRequest.alloc.init;
    request.recognitionLevel = 1;
    request.usesLanguageCorrection = true;
    request.automaticallyDetectsLanguage = true;
    var handler = $.VNImageRequestHandler.alloc.initWithURLOptions(url, {});
    var error = $();
    var ok = handler.performRequestsError($([request]), error);
    if (!ok) {
        throw new Error($(error.localizedDescription).js);
    }
    var lines = request.results.js.map(function (observation) {
        var candidates = observation.topCandidates(1).js;
        return candidates.length ? candidates[0].string.js : "";
    }).filter(function (line) {
        return line.length > 0;
    });
    return JSON.stringify({text: lines.join("\n"), lines: lines.length});
}
"""


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
    audit_arguments = arguments
    if name in ("run_applescript", "chrome_eval") and isinstance(arguments, dict):
        field = "script" if name == "run_applescript" else "javascript"
        script = arguments.get(field)
        if isinstance(script, str):
            encoded = script.encode("utf-8")
            audit_arguments = dict(arguments)
            audit_arguments[field] = {
                "bytes": len(encoded),
                "sha256": hashlib.sha256(encoded).hexdigest(),
            }
    line = "%s\t%s\tok=%s\t%s\t%s\n" % (
        datetime.now(timezone.utc).isoformat(),
        name,
        ok,
        json.dumps(audit_arguments, sort_keys=True, default=str),
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


def _decode_output(value):
    return (value or b"").decode("utf-8", "replace")


def tool_run_applescript(args):
    script = args.get("script")
    if not isinstance(script, str) or not script:
        raise ToolError("script is required")
    encoded = script.encode("utf-8")
    if len(encoded) > SCRIPT_MAX:
        raise ToolError("script exceeds %d bytes" % SCRIPT_MAX)
    timeout = args.get("timeout_seconds", 30)
    if isinstance(timeout, bool) or not isinstance(timeout, int) or not 1 <= timeout <= 120:
        raise ToolError("timeout_seconds must be an integer from 1 to 120")
    try:
        proc = run(["osascript"], timeout=timeout, input_bytes=encoded)
    except subprocess.TimeoutExpired:
        raise ToolError("AppleScript timed out after %d seconds" % timeout)
    stdout = proc.stdout or b""
    stderr = proc.stderr or b""
    if len(stdout) + len(stderr) > SCRIPT_OUTPUT_MAX:
        raise ToolError("AppleScript output exceeds %d bytes" % SCRIPT_OUTPUT_MAX)
    if proc.returncode != 0:
        raise ToolError(_decode_output(stderr or stdout).strip() or "osascript failed")
    result = {"stdout": _decode_output(stdout).rstrip("\n"), "exit_code": 0}
    if stderr:
        result["stderr"] = _decode_output(stderr).rstrip("\n")
    return result


def _window_list():
    proc = run(["osascript", "-l", "JavaScript", "-e", _WINDOW_LIST_JXA], timeout=15)
    if proc.returncode != 0:
        raise ToolError(_decode_output(proc.stderr or proc.stdout).strip() or "window listing failed")
    try:
        windows = json.loads(_decode_output(proc.stdout))
    except (TypeError, ValueError) as exc:
        raise ToolError("invalid window list: %s" % exc)
    if not isinstance(windows, list):
        raise ToolError("invalid window list response")
    return windows


def tool_list_windows(args):
    windows = _window_list()
    app = args.get("app")
    if app is not None:
        if not isinstance(app, str) or not app:
            raise ToolError("app must be a non-empty string")
        wanted = app.casefold()
        windows = [window for window in windows if str(window.get("app", "")).casefold() == wanted]
    return {"windows": windows, "count": len(windows)}


def _capture_window(windows, window_id):
    for window in windows:
        if window.get("window_id") == window_id:
            return window
    raise ToolError("no visible normal window with id %s; call list_windows again" % window_id)


def _ocr_image(path):
    proc = run(["osascript", "-l", "JavaScript", "-e", _OCR_JXA, path], timeout=60)
    if proc.returncode != 0:
        raise ToolError(_decode_output(proc.stderr or proc.stdout).strip() or "OCR failed")
    try:
        result = json.loads(_decode_output(proc.stdout))
    except (TypeError, ValueError) as exc:
        raise ToolError("invalid OCR response: %s" % exc)
    if not isinstance(result, dict) or not isinstance(result.get("text"), str):
        raise ToolError("invalid OCR response")
    return result


def tool_screenshot(args):
    target = args.get("target", "display")
    if target not in ("display", "region", "frontmost_window", "window"):
        raise ToolError("target must be display, region, frontmost_window, or window")
    include_ocr = args.get("include_ocr", False)
    if not isinstance(include_ocr, bool):
        raise ToolError("include_ocr must be a boolean")

    metadata = {"target": target}
    if target == "display":
        display = args.get("display", 1)
        if isinstance(display, bool) or not isinstance(display, int) or display < 1:
            raise ToolError("display must be a positive integer")
        try:
            display_info = mac_ui.display_bounds(display)
        except mac_ui.UIError as exc:
            raise ToolError(str(exc))
        command = ["screencapture", "-x", "-D%d" % display]
        metadata["display"] = display
        metadata["logical_bounds"] = display_info["bounds"]
        metadata["display_scale_factor"] = display_info["scale_factor"]
    elif target == "region":
        region = {key: args.get(key) for key in ("x", "y", "width", "height")}
        if any(isinstance(value, bool) or not isinstance(value, int) for value in region.values()):
            raise ToolError("x, y, width, and height must be integers when target is region")
        if region["width"] < 1 or region["height"] < 1:
            raise ToolError("region width and height must be positive")
        command = [
            "screencapture",
            "-x",
            "-R%d,%d,%d,%d"
            % (region["x"], region["y"], region["width"], region["height"]),
        ]
        metadata["region"] = region
        metadata["logical_bounds"] = dict(region)
    else:
        windows = _window_list()
        if target == "frontmost_window":
            if not windows:
                raise ToolError("no visible normal windows")
            window = windows[0]
        else:
            window_id = args.get("window_id")
            if isinstance(window_id, bool) or not isinstance(window_id, int) or window_id < 1:
                raise ToolError("window_id is required when target is window")
            window = _capture_window(windows, window_id)
        command = ["screencapture", "-x", "-o", "-l%d" % window["window_id"]]
        metadata["window"] = window
        metadata["logical_bounds"] = dict(window["bounds"])

    fd, path = tempfile.mkstemp(prefix="cws-screenshot-", suffix=".png")
    os.close(fd)
    _unlink(path)
    try:
        proc = run(command + [path], timeout=30)
        if proc.returncode != 0:
            raise ToolError(_decode_output(proc.stderr or proc.stdout).strip() or "screencapture failed")
        data = _read_bytes(path)
        if not data or not data.startswith(PNG_MAGIC):
            raise ToolError("screencapture did not produce a PNG")
        if len(data) > PNG_MAX:
            raise ToolError("screenshot exceeds %d bytes" % PNG_MAX)
        metadata["bytes"] = len(data)
        try:
            pixel_width, pixel_height = mac_ui.png_size(data)
            capture = CAPTURES.register(metadata, pixel_width, pixel_height)
        except mac_ui.UIError as exc:
            raise ToolError(str(exc))
        metadata.update(
            {
                "screenshot_id": capture["screenshot_id"],
                "pixel_width": pixel_width,
                "pixel_height": pixel_height,
                "scale_x": capture["scale_x"],
                "scale_y": capture["scale_y"],
            }
        )
        result = {
            "_mcp_image": {
                "data": base64.b64encode(data).decode("ascii"),
                "mimeType": "image/png",
            },
            "metadata": metadata,
        }
        if include_ocr:
            try:
                ocr = _ocr_image(path)
                metadata["ocr_lines"] = ocr.get("lines")
                result["ocr_text"] = ocr["text"]
            except ToolError as exc:
                metadata["ocr_error"] = str(exc)
        return result
    finally:
        _unlink(path)


def _capture_context(screenshot_id, activate):
    if not isinstance(screenshot_id, str) or not screenshot_id:
        raise ToolError("screenshot_id is required")
    try:
        capture = CAPTURES.get(screenshot_id)
        if activate and capture.get("window_id") is not None:
            mac_ui.raise_window(capture.get("window_pid"), capture.get("window_title"))
        return capture
    except mac_ui.UIError as exc:
        raise ToolError(str(exc))


def _capture_point(args):
    screenshot_id = args.get("screenshot_id")
    activate = args.get("activate", True)
    if not isinstance(activate, bool):
        raise ToolError("activate must be a boolean")
    capture = _capture_context(screenshot_id, activate)
    x = args.get("x")
    y = args.get("y")
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        raise ToolError("x must be a number")
    if isinstance(y, bool) or not isinstance(y, (int, float)):
        raise ToolError("y must be a number")
    windows = _window_list() if capture.get("window_id") is not None else []
    try:
        return CAPTURES.resolve_point(screenshot_id, x, y, windows=windows)
    except mac_ui.UIError as exc:
        raise ToolError(str(exc))


def tool_click(args):
    point = _capture_point(args)
    try:
        mac_ui.click(
            point["x"],
            point["y"],
            button=args.get("button", "left"),
            clicks=args.get("clicks", 1),
        )
    except mac_ui.UIError as exc:
        raise ToolError(str(exc))
    return {"clicked": True, "global_point": {"x": point["x"], "y": point["y"]}}


def tool_type_text(args):
    text = args.get("text")
    if not isinstance(text, str):
        raise ToolError("text must be a string")
    screenshot_id = args.get("screenshot_id")
    if screenshot_id is not None:
        activate = args.get("activate", True)
        if not isinstance(activate, bool):
            raise ToolError("activate must be a boolean")
        _capture_context(screenshot_id, activate)
    try:
        mac_ui.type_text(text)
    except mac_ui.UIError as exc:
        raise ToolError(str(exc))
    return {"typed": True, "characters": len(text)}


def tool_key(args):
    screenshot_id = args.get("screenshot_id")
    if screenshot_id is not None:
        activate = args.get("activate", True)
        if not isinstance(activate, bool):
            raise ToolError("activate must be a boolean")
        _capture_context(screenshot_id, activate)
    modifiers = args.get("modifiers") or []
    if not isinstance(modifiers, list):
        raise ToolError("modifiers must be an array")
    try:
        mac_ui.press_key(args.get("key"), modifiers)
    except mac_ui.UIError as exc:
        raise ToolError(str(exc))
    return {"pressed": args.get("key"), "modifiers": modifiers}


def tool_scroll(args):
    point = _capture_point(args)
    try:
        mac_ui.scroll(
            point["x"],
            point["y"],
            args.get("delta_x", 0),
            args.get("delta_y", 0),
        )
    except mac_ui.UIError as exc:
        raise ToolError(str(exc))
    return {
        "scrolled": True,
        "global_point": {"x": point["x"], "y": point["y"]},
        "delta_x": args.get("delta_x", 0),
        "delta_y": args.get("delta_y", 0),
    }


def tool_chrome_list_tabs(_args):
    try:
        tabs = chrome_control.list_tabs()
    except chrome_control.ChromeError as exc:
        raise ToolError(str(exc))
    return {"tabs": tabs, "count": len(tabs)}


def _push_generated_bytes(data, remote_path, workspace_id, suffix):
    fd, local_path = tempfile.mkstemp(prefix="cws-generated-", suffix=suffix)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        pushed = tool_push_to_cws(
            {
                "local_path": local_path,
                "remote_path": remote_path,
                "workspace_id": workspace_id,
                "delete_source": True,
            }
        )
        return pushed["remote_path"]
    finally:
        _unlink(local_path)


def tool_chrome_eval(args):
    try:
        result = chrome_control.evaluate(
            tab_id=args.get("tab_id"),
            url=args.get("url"),
            source=args.get("javascript"),
            timeout=args.get("timeout_seconds", 30),
        )
    except chrome_control.ChromeError as exc:
        raise ToolError(str(exc))
    remote_path = args.get("remote_path")
    if remote_path or result["bytes"] > CHROME_INLINE_MAX:
        if not remote_path:
            remote_path = "~/CWS-outbox/chrome-eval-%s.json" % uuid.uuid4().hex[:12]
        destination = _push_generated_bytes(
            result["serialized"].encode("utf-8"),
            remote_path,
            args.get("workspace_id"),
            ".json",
        )
        return {
            "remote_path": destination,
            "bytes": result["bytes"],
            "tab": result["tab"],
        }
    return {"value": result["value"], "bytes": result["bytes"], "tab": result["tab"]}


def tool_chrome_fetch(args):
    timeout = args.get("timeout_seconds", 60)
    if isinstance(timeout, bool) or not isinstance(timeout, int) or not 1 <= timeout <= 120:
        raise ToolError("timeout_seconds must be an integer from 1 to 120")
    try:
        result = chrome_control.fetch(
            args.get("url"),
            tab_id=args.get("tab_id"),
            timeout=timeout,
        )
    except chrome_control.ChromeError as exc:
        raise ToolError(str(exc))
    parsed = urlparse(args.get("url") or "")
    basename = os.path.basename(parsed.path.rstrip("/")) or "chrome-download"
    remote_path = args.get("remote_path") or "~/CWS-outbox/%s" % basename
    destination = _push_generated_bytes(
        result["body"],
        remote_path,
        args.get("workspace_id"),
        os.path.splitext(basename)[1] or ".bin",
    )
    metadata = result["metadata"]
    return {
        "remote_path": destination,
        "bytes": len(result["body"]),
        "status": metadata.get("status"),
        "ok": metadata.get("ok"),
        "final_url": metadata.get("final_url"),
        "content_type": metadata.get("content_type"),
        "headers": metadata.get("headers"),
        "tab": result["tab"],
    }


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


def _unlink(path):
    if not path:
        return
    try:
        os.unlink(path)
    except OSError:
        pass


def _tmp_path(suffix):
    fd, path = tempfile.mkstemp(prefix="cws-clipboard-", suffix=suffix)
    os.close(fd)
    return path


def _read_bytes(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError:
        return None


def _osascript(script):
    proc = run(["osascript", "-e", script], timeout=15)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or b"").decode("utf-8", "replace").strip()
        raise RuntimeError(err or "osascript failed")
    return (proc.stdout or b"").decode("utf-8", "replace").strip()


def _write_clipboard_class(out_path, class_expr):
    script = (
        "set outPath to POSIX file %s\n"
        "try\n"
        "  set clipData to the clipboard as %s\n"
        "  set fh to open for access outPath with write permission\n"
        "  set eof of fh to 0\n"
        "  write clipData to fh\n"
        "  close access fh\n"
        "  return \"ok\"\n"
        "on error\n"
        "  try\n"
        "    close access outPath\n"
        "  end try\n"
        "  return \"\"\n"
        "end try"
    ) % (json.dumps(out_path), class_expr)
    return _osascript(script) == "ok"


def _sips_png(src):
    dst = _tmp_path(".png")
    try:
        proc = run(["sips", "-s", "format", "png", src, "--out", dst], timeout=30)
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or b"").decode("utf-8", "replace").strip()
            raise RuntimeError(err or "sips failed")
        data = _read_bytes(dst)
        if not data or not data.startswith(PNG_MAGIC):
            raise RuntimeError("sips did not produce a PNG")
        return data
    finally:
        _unlink(dst)


def _clipboard_pngf():
    path = _tmp_path(".png")
    try:
        if not _write_clipboard_class(path, "«class PNGf»"):
            return None
        data = _read_bytes(path)
        if data and data.startswith(PNG_MAGIC) and len(data) > 0:
            return data
        return None
    finally:
        _unlink(path)


def _clipboard_finder_file():
    script = (
        "try\n"
        "  return POSIX path of (the clipboard as alias)\n"
        "on error\n"
        "  try\n"
        "    return POSIX path of (the clipboard as «class furl»)\n"
        "  on error\n"
        "    return \"\"\n"
        "  end try\n"
        "end try"
    )
    path = _osascript(script)
    if not path or not os.path.isfile(path):
        return None
    suffix = os.path.splitext(path)[1].lower()
    if suffix not in _IMAGE_SUFFIXES:
        return None
    return _sips_png(path)


def _clipboard_tiff():
    path = _tmp_path(".tiff")
    try:
        if not _write_clipboard_class(path, "TIFF picture"):
            if not _write_clipboard_class(path, "«class TIFF»"):
                return None
        if not os.path.isfile(path) or os.path.getsize(path) <= 0:
            return None
        return _sips_png(path)
    finally:
        _unlink(path)


def clipboard_png_bytes():
    png = _clipboard_pngf()
    if png is not None:
        return png
    png = _clipboard_finder_file()
    if png is not None:
        return png
    return _clipboard_tiff()


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
    "run_applescript": tool_run_applescript,
    "list_windows": tool_list_windows,
    "screenshot": tool_screenshot,
    "click": tool_click,
    "type_text": tool_type_text,
    "key": tool_key,
    "scroll": tool_scroll,
    "chrome_list_tabs": tool_chrome_list_tabs,
    "chrome_eval": tool_chrome_eval,
    "chrome_fetch": tool_chrome_fetch,
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
        if self.path == "/clipboard.png":
            try:
                data = clipboard_png_bytes()
            except Exception as exc:
                audit("clipboard.png", {}, False, str(exc))
                write_json(self, 500, {"error": str(exc)})
                return
            if data is None:
                audit("clipboard.png", {}, True, "bytes=0")
                write_bytes(self, 204, b"", None)
                return
            if len(data) > PNG_MAX:
                audit("clipboard.png", {}, False, "bytes=%d" % len(data))
                write_json(self, 413, {"error": "too large"})
                return
            audit("clipboard.png", {}, True, "bytes=%d" % len(data))
            write_bytes(self, 200, data, "image/png")
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

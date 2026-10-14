"""Current-profile Google Chrome automation through Apple Events."""

from __future__ import print_function

import base64
import hashlib
import json
import subprocess
import time
import uuid
from urllib.parse import urlsplit


CHUNK_CHARS = 128 * 1024
POLL_SECONDS = 0.2

_LIST_TABS_JXA = r"""
function run() {
    var chrome = Application("Google Chrome");
    return JSON.stringify(chrome.windows().map(function (win) {
        return {
            window_id: String(win.id()),
            active_tab_index: Number(win.activeTabIndex()),
            tabs: win.tabs().map(function (tab, index) {
                return {
                    index: index + 1,
                    title: String(tab.title() || ""),
                    url: String(tab.url() || ""),
                    loading: Boolean(tab.loading())
                };
            })
        };
    }));
}
"""

_EXECUTE_JXA = r"""
function run(argv) {
    var target = JSON.parse(argv[0]);
    var chrome = Application("Google Chrome");
    var windows = chrome.windows();
    for (var i = 0; i < windows.length; i++) {
        if (String(windows[i].id()) !== String(target.window_id)) {
            continue;
        }
        var tabs = windows[i].tabs();
        if (target.index < 1 || target.index > tabs.length) {
            throw new Error("Chrome tab index is stale; call chrome_list_tabs again");
        }
        var tab = tabs[target.index - 1];
        if (String(tab.url() || "") !== target.url) {
            throw new Error("Chrome tab navigated or moved; call chrome_list_tabs again");
        }
        return tab.execute({javascript: argv[1]});
    }
    throw new Error("Chrome window is gone; call chrome_list_tabs again");
}
"""

_SET_ACTIVE_JXA = r"""
function run(argv) {
    var target = JSON.parse(argv[0]);
    var chrome = Application("Google Chrome");
    var windows = chrome.windows();
    for (var i = 0; i < windows.length; i++) {
        if (String(windows[i].id()) !== String(target.window_id)) continue;
        var previous = Number(windows[i].activeTabIndex());
        windows[i].activeTabIndex = Number(target.index);
        return JSON.stringify({previous_index: previous});
    }
    throw new Error("Chrome window is gone; call chrome_list_tabs again");
}
"""


class ChromeError(Exception):
    pass


def _run(command, timeout=30):
    return subprocess.run(command, capture_output=True, timeout=timeout, check=False)


def _osascript(script, arguments=None, timeout=30):
    command = ["osascript", "-l", "JavaScript", "-e", script]
    command.extend(arguments or [])
    try:
        proc = _run(command, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise ChromeError("Chrome automation timed out")
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or b"").decode("utf-8", "replace").strip()
        if "Apple Events" in detail:
            detail += (
                " (enable Chrome > View > Developer > Allow JavaScript from Apple Events)"
            )
        raise ChromeError(detail or "Chrome automation failed")
    return (proc.stdout or b"").decode("utf-8", "replace").strip()


def _tab_id(window_id, url, occurrence):
    value = "%s\0%s\0%d" % (window_id, url, occurrence)
    return "tab_" + hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


def list_tabs():
    try:
        windows = json.loads(_osascript(_LIST_TABS_JXA))
    except (TypeError, ValueError) as exc:
        raise ChromeError("invalid Chrome tab list: %s" % exc)
    tabs = []
    occurrences = {}
    for window in windows:
        window_id = str(window.get("window_id"))
        active_index = window.get("active_tab_index")
        for tab in window.get("tabs") or []:
            url = tab.get("url") or ""
            key = (window_id, url)
            occurrence = occurrences.get(key, 0)
            occurrences[key] = occurrence + 1
            tabs.append(
                {
                    "tab_id": _tab_id(window_id, url, occurrence),
                    "window_id": window_id,
                    "index": tab.get("index"),
                    "title": tab.get("title") or "",
                    "url": url,
                    "loading": bool(tab.get("loading")),
                    "active": tab.get("index") == active_index,
                }
            )
    return tabs


def _origin(url):
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        return None
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == "https" else 80
    return (parsed.scheme.lower(), parsed.hostname.lower(), port)


def resolve_tab(tab_id=None, url=None, required_origin=None):
    if bool(tab_id) == bool(url):
        raise ChromeError("provide exactly one of tab_id or url")
    tabs = list_tabs()
    if tab_id:
        matches = [tab for tab in tabs if tab["tab_id"] == tab_id]
    else:
        matches = [tab for tab in tabs if tab["url"] == url]
    if not matches:
        raise ChromeError("no matching Chrome tab; call chrome_list_tabs")
    tab = matches[0]
    if required_origin is not None and _origin(tab["url"]) != required_origin:
        raise ChromeError("selected tab does not match the requested URL origin")
    return tab


def _execute(tab, source, timeout=30):
    selector = json.dumps(
        {"window_id": tab["window_id"], "index": tab["index"], "url": tab["url"]}
    )
    return _osascript(_EXECUTE_JXA, [selector, source], timeout=timeout)


def _set_active_tab(tab):
    selector = json.dumps({"window_id": tab["window_id"], "index": tab["index"]})
    try:
        return json.loads(_osascript(_SET_ACTIVE_JXA, [selector]))
    except (TypeError, ValueError) as exc:
        raise ChromeError("could not activate Chrome tab: %s" % exc)


def _restore_active_tab(tab, previous):
    if not previous:
        return
    selector = {
        "window_id": tab["window_id"],
        "index": previous.get("previous_index"),
    }
    try:
        _osascript(_SET_ACTIVE_JXA, [json.dumps(selector)])
    except ChromeError:
        pass


def _job_store_source():
    return (
        "globalThis.__cwsHostJobs = globalThis.__cwsHostJobs || "
        "Object.create(null);"
    )


def _start_eval(tab, source, job_id):
    script = r"""
(() => {
  %s
  const id = %s;
  const source = %s;
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  globalThis.__cwsHostJobs[id] = {status: "pending", kind: "json"};
  let fn;
  try {
    fn = new AsyncFunction("return await (" + source + "\n);");
  } catch (_) {
    fn = new AsyncFunction(source);
  }
  Promise.resolve().then(() => fn()).then(value => {
    const replacer = (_key, item) =>
      typeof item === "bigint" ? String(item) : item;
    let data = JSON.stringify(value, replacer);
    if (data === undefined) data = JSON.stringify(String(value));
    globalThis.__cwsHostJobs[id] = {
      status: "done", kind: "json", data, length: data.length
    };
  }).catch(error => {
    globalThis.__cwsHostJobs[id] = {
      status: "error",
      error: String(error && error.message || error),
      stack: String(error && error.stack || "")
    };
  });
  return JSON.stringify({status: "started", job_id: id});
})()
""" % (_job_store_source(), json.dumps(job_id), json.dumps(source))
    _execute(tab, script)


def _start_fetch(tab, url, job_id):
    script = r"""
(() => {
  %s
  const id = %s;
  const url = %s;
  globalThis.__cwsHostJobs[id] = {status: "pending", kind: "bytes"};
  fetch(url, {credentials: "include"}).then(async response => {
    const bytes = new Uint8Array(await response.arrayBuffer());
    globalThis.__cwsHostJobs[id] = {
      status: "done",
      kind: "bytes",
      data: bytes,
      length: bytes.length,
      metadata: {
        status: response.status,
        ok: response.ok,
        final_url: response.url,
        content_type: response.headers.get("content-type"),
        headers: Object.fromEntries(response.headers.entries())
      }
    };
  }).catch(error => {
    globalThis.__cwsHostJobs[id] = {
      status: "error",
      error: String(error && error.message || error),
      stack: String(error && error.stack || "")
    };
  });
  return JSON.stringify({status: "started", job_id: id});
})()
""" % (_job_store_source(), json.dumps(job_id), json.dumps(url))
    _execute(tab, script)


def _job_status(tab, job_id):
    script = r"""
(() => {
  %s
  const job = globalThis.__cwsHostJobs[%s];
  if (!job) return JSON.stringify({status: "missing"});
  return JSON.stringify({
    status: job.status,
    kind: job.kind,
    length: job.length,
    metadata: job.metadata,
    error: job.error,
    stack: job.stack
  });
})()
""" % (_job_store_source(), json.dumps(job_id))
    raw = _execute(tab, script)
    try:
        return json.loads(raw)
    except (TypeError, ValueError) as exc:
        raise ChromeError("invalid Chrome job status: %s" % exc)


def _wait(tab, job_id, timeout):
    deadline = time.monotonic() + timeout
    while True:
        status = _job_status(tab, job_id)
        if status.get("status") == "done":
            return status
        if status.get("status") == "error":
            detail = status.get("error") or "JavaScript failed"
            stack = status.get("stack")
            if stack:
                detail += "\n" + stack
            raise ChromeError(detail)
        if status.get("status") == "missing":
            raise ChromeError("Chrome job disappeared, probably because the tab navigated")
        if time.monotonic() >= deadline:
            raise ChromeError("Chrome JavaScript timed out after %d seconds" % timeout)
        time.sleep(POLL_SECONDS)


def _read_text_chunk(tab, job_id, offset, size):
    script = r"""
(() => {
  const job = globalThis.__cwsHostJobs[%s];
  if (!job || job.status !== "done" || job.kind !== "json") {
    throw new Error("Chrome JSON job is unavailable");
  }
  return JSON.stringify({chunk: job.data.slice(%d, %d)});
})()
""" % (json.dumps(job_id), offset, offset + size)
    try:
        return json.loads(_execute(tab, script))["chunk"]
    except (KeyError, TypeError, ValueError) as exc:
        raise ChromeError("invalid Chrome result chunk: %s" % exc)


def _read_bytes_chunk(tab, job_id, offset, size):
    script = r"""
(() => {
  const job = globalThis.__cwsHostJobs[%s];
  if (!job || job.status !== "done" || job.kind !== "bytes") {
    throw new Error("Chrome byte job is unavailable");
  }
  const bytes = job.data.subarray(%d, %d);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 32768) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
  }
  return JSON.stringify({chunk: btoa(binary)});
})()
""" % (json.dumps(job_id), offset, offset + size)
    try:
        encoded = json.loads(_execute(tab, script))["chunk"]
        return base64.b64decode(encoded)
    except (KeyError, TypeError, ValueError) as exc:
        raise ChromeError("invalid Chrome byte chunk: %s" % exc)


def _cleanup(tab, job_id):
    script = "delete globalThis.__cwsHostJobs[%s]; true" % json.dumps(job_id)
    try:
        _execute(tab, script)
    except ChromeError:
        pass


def evaluate(tab_id=None, url=None, source=None, timeout=30):
    if not isinstance(source, str) or not source:
        raise ChromeError("javascript is required")
    if isinstance(timeout, bool) or not isinstance(timeout, int) or not 1 <= timeout <= 120:
        raise ChromeError("timeout_seconds must be an integer from 1 to 120")
    tab = resolve_tab(tab_id=tab_id, url=url)
    job_id = "job_" + uuid.uuid4().hex
    previous = _set_active_tab(tab)
    try:
        _start_eval(tab, source, job_id)
        status = _wait(tab, job_id, timeout)
        length = int(status.get("length") or 0)
        pieces = []
        for offset in range(0, length, CHUNK_CHARS):
            pieces.append(_read_text_chunk(tab, job_id, offset, CHUNK_CHARS))
        serialized = "".join(pieces)
        try:
            value = json.loads(serialized)
        except (TypeError, ValueError):
            value = serialized
        return {
            "value": value,
            "serialized": serialized,
            "bytes": len(serialized.encode("utf-8")),
            "tab": tab,
        }
    finally:
        _cleanup(tab, job_id)
        _restore_active_tab(tab, previous)


def fetch(url, tab_id=None, timeout=60):
    if not isinstance(url, str) or _origin(url) is None or not url.startswith("https://"):
        raise ChromeError("url must be an https URL")
    origin = _origin(url)
    if tab_id:
        tab = resolve_tab(tab_id=tab_id, required_origin=origin)
    else:
        tabs = [tab for tab in list_tabs() if _origin(tab["url"]) == origin]
        if not tabs:
            raise ChromeError("open a Chrome tab on %s before fetching this URL" % origin[1])
        tab = next((item for item in tabs if item["active"]), tabs[0])
    job_id = "job_" + uuid.uuid4().hex
    previous = _set_active_tab(tab)
    try:
        _start_fetch(tab, url, job_id)
        status = _wait(tab, job_id, timeout)
        length = int(status.get("length") or 0)
        body = bytearray()
        for offset in range(0, length, CHUNK_CHARS):
            body.extend(_read_bytes_chunk(tab, job_id, offset, CHUNK_CHARS))
        return {
            "body": bytes(body),
            "metadata": status.get("metadata") or {},
            "tab": tab,
        }
    finally:
        _cleanup(tab, job_id)
        _restore_active_tab(tab, previous)

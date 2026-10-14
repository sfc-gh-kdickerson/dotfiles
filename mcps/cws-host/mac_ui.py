"""Screenshot geometry and macOS input helpers. Stdlib only."""

from __future__ import print_function

import json
import subprocess
import threading
import time
import uuid
from collections import OrderedDict


CAPTURE_TTL_SECONDS = 30 * 60
CAPTURE_MAX = 100

_DISPLAY_JXA = r"""
ObjC.import("AppKit");
function run() {
    var screens = $.NSScreen.screens.js;
    var primaryHeight = Number(ObjC.deepUnwrap(screens[0].frame).size.height);
    return JSON.stringify(screens.map(function (screen, index) {
        var frame = ObjC.deepUnwrap(screen.frame);
        return {
            display: index + 1,
            bounds: {
                x: Number(frame.origin.x),
                y: primaryHeight - Number(frame.origin.y) - Number(frame.size.height),
                width: Number(frame.size.width),
                height: Number(frame.size.height)
            },
            scale_factor: Number(screen.backingScaleFactor)
        };
    }));
}
"""

_MOUSE_JXA = r"""
ObjC.import("CoreGraphics");
function run(argv) {
    var action = JSON.parse(argv[0]);
    var point = $.CGPointMake(action.x, action.y);
    var types = {
        left: [$.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp, $.kCGMouseButtonLeft],
        right: [$.kCGEventRightMouseDown, $.kCGEventRightMouseUp, $.kCGMouseButtonRight],
        middle: [$.kCGEventOtherMouseDown, $.kCGEventOtherMouseUp, $.kCGMouseButtonCenter]
    };
    var spec = types[action.button];
    for (var i = 1; i <= action.clicks; i++) {
        var down = $.CGEventCreateMouseEvent(null, spec[0], point, spec[2]);
        var up = $.CGEventCreateMouseEvent(null, spec[1], point, spec[2]);
        $.CGEventSetIntegerValueField(down, $.kCGMouseEventClickState, i);
        $.CGEventSetIntegerValueField(up, $.kCGMouseEventClickState, i);
        $.CGEventPost($.kCGHIDEventTap, down);
        $.CGEventPost($.kCGHIDEventTap, up);
    }
    return JSON.stringify({clicked: true});
}
"""

_SCROLL_JXA = r"""
ObjC.import("CoreGraphics");
function run(argv) {
    var action = JSON.parse(argv[0]);
    var move = $.CGEventCreateMouseEvent(
        null, $.kCGEventMouseMoved, $.CGPointMake(action.x, action.y), $.kCGMouseButtonLeft
    );
    $.CGEventPost($.kCGHIDEventTap, move);
    var event = $.CGEventCreateScrollWheelEvent(
        null, $.kCGScrollEventUnitPixel, 2, action.delta_y, action.delta_x
    );
    $.CGEventPost($.kCGHIDEventTap, event);
    return JSON.stringify({scrolled: true});
}
"""

_TYPE_JXA = r"""
function run(argv) {
    Application("System Events").keystroke(argv[0]);
    return JSON.stringify({typed: true});
}
"""

KEY_CODES = {
    "return": 36,
    "enter": 36,
    "tab": 48,
    "space": 49,
    "delete": 51,
    "backspace": 51,
    "escape": 53,
    "esc": 53,
    "command": 55,
    "shift": 56,
    "caps_lock": 57,
    "option": 58,
    "control": 59,
    "right_shift": 60,
    "right_option": 61,
    "right_control": 62,
    "function": 63,
    "f17": 64,
    "volume_up": 72,
    "volume_down": 73,
    "mute": 74,
    "f18": 79,
    "f19": 80,
    "f20": 90,
    "f5": 96,
    "f6": 97,
    "f7": 98,
    "f3": 99,
    "f8": 100,
    "f9": 101,
    "f11": 103,
    "f13": 105,
    "f16": 106,
    "f14": 107,
    "f10": 109,
    "f12": 111,
    "f15": 113,
    "help": 114,
    "home": 115,
    "page_up": 116,
    "forward_delete": 117,
    "f4": 118,
    "end": 119,
    "f2": 120,
    "page_down": 121,
    "f1": 122,
    "left": 123,
    "right": 124,
    "down": 125,
    "up": 126,
}

MODIFIERS = {
    "command": "command down",
    "control": "control down",
    "option": "option down",
    "shift": "shift down",
}


class UIError(Exception):
    pass


def _run(command, timeout=30, input_bytes=None):
    return subprocess.run(
        command,
        input=input_bytes,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def _output(proc):
    return (proc.stdout or b"").decode("utf-8", "replace").strip()


def _run_jxa(script, argument=None, timeout=30):
    command = ["osascript", "-l", "JavaScript", "-e", script]
    if argument is not None:
        command.append(argument)
    proc = _run(command, timeout=timeout)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or b"").decode("utf-8", "replace").strip()
        raise UIError(detail or "macOS automation failed")
    return _output(proc)


def display_bounds(display):
    try:
        displays = json.loads(_run_jxa(_DISPLAY_JXA))
    except (TypeError, ValueError) as exc:
        raise UIError("invalid display geometry: %s" % exc)
    for item in displays:
        if item.get("display") == display:
            return item
    raise UIError("display %s does not exist" % display)


def png_size(data):
    if not data or len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise UIError("not a PNG")
    return (
        int.from_bytes(data[16:20], "big"),
        int.from_bytes(data[20:24], "big"),
    )


class CaptureRegistry:
    def __init__(self, ttl_seconds=CAPTURE_TTL_SECONDS, maximum=CAPTURE_MAX, clock=None):
        self.ttl_seconds = ttl_seconds
        self.maximum = maximum
        self.clock = clock or time.monotonic
        self._captures = OrderedDict()
        self._lock = threading.Lock()

    def _prune(self, now):
        expired = [
            key
            for key, value in self._captures.items()
            if now - value["created_at"] > self.ttl_seconds
        ]
        for key in expired:
            self._captures.pop(key, None)
        while len(self._captures) >= self.maximum:
            self._captures.popitem(last=False)

    def register(self, metadata, pixel_width, pixel_height):
        bounds = metadata.get("logical_bounds")
        if not isinstance(bounds, dict) or bounds.get("width", 0) <= 0 or bounds.get("height", 0) <= 0:
            raise UIError("capture has no usable logical bounds")
        now = self.clock()
        capture_id = uuid.uuid4().hex
        capture = {
            "screenshot_id": capture_id,
            "created_at": now,
            "pixel_width": pixel_width,
            "pixel_height": pixel_height,
            "logical_bounds": dict(bounds),
            "scale_x": float(pixel_width) / float(bounds["width"]),
            "scale_y": float(pixel_height) / float(bounds["height"]),
            "window_id": metadata.get("window", {}).get("window_id"),
            "window_pid": metadata.get("window", {}).get("pid"),
            "window_title": metadata.get("window", {}).get("title"),
        }
        with self._lock:
            self._prune(now)
            self._captures[capture_id] = capture
        return dict(capture)

    def get(self, screenshot_id):
        now = self.clock()
        with self._lock:
            self._prune(now)
            capture = self._captures.get(screenshot_id)
            if capture is None:
                raise UIError("unknown or expired screenshot_id; take a new screenshot")
            return dict(capture)

    def resolve_point(self, screenshot_id, pixel_x, pixel_y, windows=None):
        capture = self.get(screenshot_id)
        width = capture["pixel_width"]
        height = capture["pixel_height"]
        if not 0 <= pixel_x < width or not 0 <= pixel_y < height:
            raise UIError("coordinates are outside the screenshot")
        bounds = capture["logical_bounds"]
        if capture.get("window_id") is not None:
            current = None
            for window in windows or []:
                if window.get("window_id") == capture["window_id"]:
                    current = window
                    break
            if current is None:
                raise UIError("captured window is no longer visible; take a new screenshot")
            bounds = current["bounds"]
            capture["window_pid"] = current.get("pid")
            capture["window_title"] = current.get("title")
        x = float(bounds["x"]) + (float(pixel_x) / float(width)) * float(bounds["width"])
        y = float(bounds["y"]) + (float(pixel_y) / float(height)) * float(bounds["height"])
        return {"x": round(x, 3), "y": round(y, 3), "capture": capture}


def raise_window(pid, title):
    if not pid:
        return
    script = (
        'tell application "System Events"\n'
        "  set targetProcess to first process whose unix id is %d\n"
        "  set frontmost of targetProcess to true\n"
        "  try\n"
        "    perform action \"AXRaise\" of first window of targetProcess whose name is %s\n"
        "  end try\n"
        "end tell"
    ) % (pid, json.dumps(title or ""))
    proc = _run(["osascript", "-e", script], timeout=15)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or b"").decode("utf-8", "replace").strip()
        raise UIError(detail or "could not activate captured window")


def click(x, y, button="left", clicks=1):
    if button not in ("left", "right", "middle"):
        raise UIError("button must be left, right, or middle")
    if isinstance(clicks, bool) or not isinstance(clicks, int) or not 1 <= clicks <= 3:
        raise UIError("clicks must be an integer from 1 to 3")
    payload = json.dumps({"x": x, "y": y, "button": button, "clicks": clicks})
    _run_jxa(_MOUSE_JXA, payload)


def type_text(text):
    if not isinstance(text, str):
        raise UIError("text must be a string")
    _run_jxa(_TYPE_JXA, text)


def press_key(key, modifiers=None):
    key = str(key or "").lower().replace("-", "_").replace(" ", "_")
    modifiers = modifiers or []
    invalid = [
        str(item)
        for item in modifiers
        if not isinstance(item, str) or item not in MODIFIERS
    ]
    if invalid:
        raise UIError("unknown modifiers: %s" % ", ".join(invalid))
    using = ""
    if modifiers:
        using = " using {%s}" % ", ".join(MODIFIERS[item] for item in modifiers)
    if key in KEY_CODES:
        action = "key code %d" % KEY_CODES[key]
    elif len(key) == 1:
        action = "keystroke %s" % json.dumps(key)
    else:
        raise UIError("unknown key: %s" % key)
    script = 'tell application "System Events" to %s%s' % (action, using)
    proc = _run(["osascript", "-e", script], timeout=15)
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or b"").decode("utf-8", "replace").strip()
        raise UIError(detail or "key press failed")


def scroll(x, y, delta_x, delta_y):
    values = (delta_x, delta_y)
    if any(isinstance(value, bool) or not isinstance(value, int) for value in values):
        raise UIError("scroll deltas must be integers")
    if delta_x == 0 and delta_y == 0:
        raise UIError("at least one scroll delta must be non-zero")
    payload = json.dumps(
        {"x": x, "y": y, "delta_x": delta_x, "delta_y": delta_y}
    )
    _run_jxa(_SCROLL_JXA, payload)

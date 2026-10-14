"""Single source of truth for MCP tool schemas. No generic exec."""

TOOLS = [
    {
        "name": "host_status",
        "description": (
            "Whether the Mac host tunnel is up. Always answered by the CWS "
            "facade, even when the laptop is disconnected."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "host_info",
        "description": "Mac home, hostname, Chrome availability, inbox/outbox paths.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "open_url",
        "description": "Open an https URL in Google Chrome on the Mac.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "https URL to open"},
            },
            "required": ["url"],
            "additionalProperties": False,
        },
    },
    {
        "name": "open_path",
        "description": "Open a local Mac path in the default application.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute or ~ path on the Mac"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "reveal_in_finder",
        "description": "Reveal a local Mac path in Finder.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "notify",
        "description": "Show a macOS notification on the laptop.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "message": {"type": "string"},
            },
            "required": ["message"],
            "additionalProperties": False,
        },
    },
    {
        "name": "run_applescript",
        "description": (
            "Run unrestricted AppleScript on the Mac. This can control applications "
            "and is equivalent to arbitrary code execution on the laptop."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "script": {
                    "type": "string",
                    "description": "AppleScript source to execute",
                    "minLength": 1,
                    "maxLength": 100000,
                },
                "timeout_seconds": {
                    "type": "integer",
                    "description": "Execution timeout in seconds (default 30, maximum 120)",
                    "minimum": 1,
                    "maximum": 120,
                    "default": 30,
                },
            },
            "required": ["script"],
            "additionalProperties": False,
        },
    },
    {
        "name": "list_windows",
        "description": (
            "List visible normal macOS windows in front-to-back order. Use a returned "
            "window_id with screenshot to capture a specific window."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "app": {
                    "type": "string",
                    "description": "Optional case-insensitive exact application-name filter",
                },
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "screenshot",
        "description": (
            "Capture a Mac display, screen region, frontmost normal window, or a "
            "specific window as an inline PNG image. Prefer region captures for small "
            "UI details so model image processing preserves their resolution."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "target": {
                    "type": "string",
                    "enum": ["display", "region", "frontmost_window", "window"],
                    "default": "display",
                },
                "display": {
                    "type": "integer",
                    "description": "1-based display number when target is display",
                    "minimum": 1,
                    "default": 1,
                },
                "window_id": {
                    "type": "integer",
                    "description": "Window ID from list_windows; required when target is window",
                    "minimum": 1,
                },
                "x": {
                    "type": "integer",
                    "description": "Global screen x coordinate; required when target is region",
                },
                "y": {
                    "type": "integer",
                    "description": "Global screen y coordinate; required when target is region",
                },
                "width": {
                    "type": "integer",
                    "description": "Region width in screen points; required when target is region",
                    "minimum": 1,
                },
                "height": {
                    "type": "integer",
                    "description": "Region height in screen points; required when target is region",
                    "minimum": 1,
                },
                "include_ocr": {
                    "type": "boolean",
                    "description": (
                        "Run macOS Vision OCR and include recognized text in the response"
                    ),
                    "default": False,
                },
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "click",
        "description": (
            "Click screenshot pixel coordinates. The screenshot_id handles Retina "
            "scaling and follows a captured window if it moved or resized."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "screenshot_id": {"type": "string"},
                "x": {"type": "number", "description": "Pixel x in the returned PNG"},
                "y": {"type": "number", "description": "Pixel y in the returned PNG"},
                "button": {
                    "type": "string",
                    "enum": ["left", "right", "middle"],
                    "default": "left",
                },
                "clicks": {"type": "integer", "minimum": 1, "maximum": 3, "default": 1},
                "activate": {
                    "type": "boolean",
                    "description": "Raise the captured window before clicking",
                    "default": True,
                },
            },
            "required": ["screenshot_id", "x", "y"],
            "additionalProperties": False,
        },
    },
    {
        "name": "type_text",
        "description": "Type Unicode text into the focused Mac control.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "screenshot_id": {
                    "type": "string",
                    "description": "Optional capture whose window should be raised first",
                },
                "activate": {"type": "boolean", "default": True},
            },
            "required": ["text"],
            "additionalProperties": False,
        },
    },
    {
        "name": "key",
        "description": "Press a named key or one-character key with optional modifiers.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "key": {
                    "type": "string",
                    "description": "For example return, tab, escape, left, f5, or a",
                },
                "modifiers": {
                    "type": "array",
                    "items": {
                        "type": "string",
                        "enum": ["command", "control", "option", "shift"],
                    },
                    "uniqueItems": True,
                    "default": [],
                },
                "screenshot_id": {"type": "string"},
                "activate": {"type": "boolean", "default": True},
            },
            "required": ["key"],
            "additionalProperties": False,
        },
    },
    {
        "name": "scroll",
        "description": (
            "Scroll at screenshot pixel coordinates. Positive delta_y scrolls up; "
            "negative delta_y scrolls down."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "screenshot_id": {"type": "string"},
                "x": {"type": "number"},
                "y": {"type": "number"},
                "delta_x": {"type": "integer", "default": 0},
                "delta_y": {"type": "integer", "default": 0},
                "activate": {"type": "boolean", "default": True},
            },
            "required": ["screenshot_id", "x", "y", "delta_y"],
            "additionalProperties": False,
        },
    },
    {
        "name": "chrome_list_tabs",
        "description": (
            "List tabs in the current Google Chrome profile with opaque IDs that can "
            "be passed to chrome_eval or chrome_fetch."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "chrome_eval",
        "description": (
            "Evaluate JavaScript in a current Chrome tab selected by tab_id or exact "
            "URL and await promises. Large results are written directly to the CWS."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "tab_id": {"type": "string"},
                "url": {"type": "string", "description": "Exact open-tab URL"},
                "javascript": {"type": "string", "minLength": 1, "maxLength": 200000},
                "timeout_seconds": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 120,
                    "default": 30,
                },
                "remote_path": {
                    "type": "string",
                    "description": "Optional CWS output path; forces file output",
                },
                "workspace_id": {"type": "string"},
            },
            "required": ["javascript"],
            "additionalProperties": False,
        },
    },
    {
        "name": "chrome_fetch",
        "description": (
            "Fetch an HTTPS URL with the cookies of a current Chrome tab on the same "
            "origin and save the response directly to the CWS."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string"},
                "tab_id": {
                    "type": "string",
                    "description": "Optional same-origin tab; otherwise one is selected",
                },
                "remote_path": {
                    "type": "string",
                    "description": "CWS destination; defaults under ~/CWS-outbox",
                },
                "workspace_id": {"type": "string"},
                "timeout_seconds": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 120,
                    "default": 60,
                },
            },
            "required": ["url"],
            "additionalProperties": False,
        },
    },
    {
        "name": "stat",
        "description": "stat a path on the Mac.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "listdir",
        "description": "List one directory on the Mac (not recursive).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pull_from_cws",
        "description": (
            "Copy a path from the cloud workspace onto the Mac via sf ws ssh. "
            "Default destination is ~/CWS-inbox/<basename>."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "remote_path": {
                    "type": "string",
                    "description": "Path on the CWS",
                },
                "local_path": {
                    "type": "string",
                    "description": "Destination on the Mac. Defaults to ~/CWS-inbox/<basename>",
                },
                "delete_source": {
                    "type": "boolean",
                    "description": "Delete the CWS path after a successful copy",
                    "default": False,
                },
                "workspace_id": {
                    "type": "string",
                    "description": "sf ws ls id. Defaults to the last connect id.",
                },
            },
            "required": ["remote_path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "push_to_cws",
        "description": (
            "Copy a path from the Mac onto the cloud workspace. "
            "Default destination is ~/CWS-outbox/<basename> on the CWS."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "local_path": {"type": "string"},
                "remote_path": {
                    "type": "string",
                    "description": "Destination on the CWS. Defaults to ~/CWS-outbox/<basename>",
                },
                "delete_source": {
                    "type": "boolean",
                    "description": "Delete the Mac path after a successful copy",
                    "default": False,
                },
                "workspace_id": {"type": "string"},
            },
            "required": ["local_path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "clipboard_get",
        "description": "Read the Mac pasteboard.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "clipboard_set",
        "description": "Set the Mac pasteboard.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
            },
            "required": ["text"],
            "additionalProperties": False,
        },
    },
]

HOST_TOOLS = [t for t in TOOLS if t["name"] != "host_status"]
TOOL_NAMES = [t["name"] for t in TOOLS]
HOST_TOOL_NAMES = [t["name"] for t in HOST_TOOLS]

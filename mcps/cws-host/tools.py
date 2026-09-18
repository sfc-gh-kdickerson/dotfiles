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

import base64
import os
import subprocess
import unittest
from types import SimpleNamespace
from unittest import mock

import facade
import host
import mac_ui
import protocol
from tools import HOST_TOOL_NAMES, TOOLS


def fake_png(width=800, height=600, payload=b""):
    return (
        host.PNG_MAGIC
        + b"\x00\x00\x00\rIHDR"
        + width.to_bytes(4, "big")
        + height.to_bytes(4, "big")
        + payload
    )


class ToolSchemaTests(unittest.TestCase):
    def test_computer_use_tools_are_exposed_by_host(self):
        names = {tool["name"] for tool in TOOLS}
        self.assertTrue({"run_applescript", "list_windows", "screenshot"} <= names)
        self.assertIn("run_applescript", HOST_TOOL_NAMES)
        screenshot = next(tool for tool in TOOLS if tool["name"] == "screenshot")
        self.assertIn("region", screenshot["inputSchema"]["properties"]["target"]["enum"])
        self.assertIn("include_ocr", screenshot["inputSchema"]["properties"])
        self.assertTrue(
            {"click", "type_text", "key", "scroll", "chrome_list_tabs", "chrome_eval", "chrome_fetch"}
            <= names
        )


class AppleScriptTests(unittest.TestCase):
    @mock.patch.object(host, "run")
    def test_executes_script_on_stdin_with_timeout(self, run):
        run.return_value = SimpleNamespace(returncode=0, stdout=b"result\n", stderr=b"")

        result = host.tool_run_applescript(
            {"script": 'tell application "Finder" to get name', "timeout_seconds": 12}
        )

        self.assertEqual(result, {"stdout": "result", "exit_code": 0})
        run.assert_called_once_with(
            ["osascript"],
            timeout=12,
            input_bytes=b'tell application "Finder" to get name',
        )

    @mock.patch.object(host, "run")
    def test_reports_timeout_as_tool_error(self, run):
        run.side_effect = subprocess.TimeoutExpired(["osascript"], 1)

        with self.assertRaisesRegex(host.ToolError, "timed out after 1 seconds"):
            host.tool_run_applescript({"script": "delay 2", "timeout_seconds": 1})

    @mock.patch.object(host, "run")
    def test_rejects_oversized_output(self, run):
        run.return_value = SimpleNamespace(
            returncode=0,
            stdout=b"x" * (host.SCRIPT_OUTPUT_MAX + 1),
            stderr=b"",
        )

        with self.assertRaisesRegex(host.ToolError, "output exceeds"):
            host.tool_run_applescript({"script": "return 1"})


class WindowTests(unittest.TestCase):
    @mock.patch.object(host, "_window_list")
    def test_filters_windows_by_exact_case_insensitive_app_name(self, window_list):
        window_list.return_value = [
            {"window_id": 1, "app": "Cursor", "title": "one"},
            {"window_id": 2, "app": "Google Chrome", "title": "two"},
        ]

        result = host.tool_list_windows({"app": "cursor"})

        self.assertEqual(result["count"], 1)
        self.assertEqual(result["windows"][0]["window_id"], 1)

    def test_specific_window_screenshot_returns_png_and_cleans_up(self):
        windows = [
            {
                "window_id": 42,
                "app": "Cursor",
                "title": "Agentic Connect Tools",
                "pid": 123,
                "bounds": {"x": 0, "y": 0, "width": 800, "height": 600},
            }
        ]
        captured = {}

        def fake_run(command, timeout=60, input_bytes=None):
            captured["command"] = command
            captured["path"] = command[-1]
            with open(command[-1], "wb") as fh:
                fh.write(fake_png(payload=b"test-image"))
            return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

        with mock.patch.object(host, "_window_list", return_value=windows):
            with mock.patch.object(host, "run", side_effect=fake_run):
                result = host.tool_screenshot({"target": "window", "window_id": 42})

        self.assertIn("-l42", captured["command"])
        self.assertFalse(os.path.exists(captured["path"]))
        self.assertEqual(
            base64.b64decode(result["_mcp_image"]["data"]),
            fake_png(payload=b"test-image"),
        )
        self.assertEqual(result["metadata"]["window"], windows[0])
        self.assertEqual(result["metadata"]["pixel_width"], 800)
        self.assertEqual(result["metadata"]["pixel_height"], 600)
        self.assertIn("screenshot_id", result["metadata"])

    def test_region_screenshot_uses_global_screen_coordinates(self):
        captured = {}

        def fake_run(command, timeout=60, input_bytes=None):
            captured["command"] = command
            with open(command[-1], "wb") as fh:
                fh.write(fake_png(1200, 800, b"region"))
            return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

        with mock.patch.object(host, "run", side_effect=fake_run):
            result = host.tool_screenshot(
                {"target": "region", "x": -200, "y": 50, "width": 600, "height": 400}
            )

        self.assertIn("-R-200,50,600,400", captured["command"])
        self.assertEqual(
            result["metadata"]["region"],
            {"x": -200, "y": 50, "width": 600, "height": 400},
        )
        self.assertEqual(result["metadata"]["scale_x"], 2.0)
        self.assertEqual(result["metadata"]["scale_y"], 2.0)

    def test_region_requires_all_integer_coordinates(self):
        with self.assertRaisesRegex(host.ToolError, "must be integers"):
            host.tool_screenshot({"target": "region", "x": 0, "y": 0, "width": 100})

    def test_screenshot_can_include_vision_ocr_text(self):
        def fake_run(command, timeout=60, input_bytes=None):
            with open(command[-1], "wb") as fh:
                fh.write(fake_png(payload=b"ocr"))
            return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

        with mock.patch.object(host, "run", side_effect=fake_run):
            with mock.patch.object(
                host, "_ocr_image", return_value={"text": "Hello world", "lines": 1}
            ):
                result = host.tool_screenshot({"target": "display", "include_ocr": True})

        self.assertEqual(result["ocr_text"], "Hello world")
        self.assertEqual(result["metadata"]["ocr_lines"], 1)

    @mock.patch.object(host, "run")
    def test_vision_ocr_parses_jxa_result(self, run):
        run.return_value = SimpleNamespace(
            returncode=0,
            stdout=b'{"text":"Hello world","lines":1}\n',
            stderr=b"",
        )

        result = host._ocr_image("/tmp/screenshot.png")

        self.assertEqual(result, {"text": "Hello world", "lines": 1})
        self.assertEqual(run.call_args.args[0][-1], "/tmp/screenshot.png")

    @mock.patch.object(host, "_read_bytes")
    @mock.patch.object(host, "run")
    def test_rejects_oversized_screenshot(self, run, read_bytes):
        run.return_value = SimpleNamespace(returncode=0, stdout=b"", stderr=b"")
        read_bytes.return_value = fake_png() + b"x" * host.PNG_MAX

        with self.assertRaisesRegex(host.ToolError, "screenshot exceeds"):
            host.tool_screenshot({"target": "display"})


class CaptureGeometryTests(unittest.TestCase):
    def test_window_coordinates_follow_current_position_and_size(self):
        registry = mac_ui.CaptureRegistry(clock=lambda: 10)
        capture = registry.register(
            {
                "logical_bounds": {"x": 100, "y": 200, "width": 800, "height": 600},
                "window": {"window_id": 42, "pid": 7, "title": "Example"},
            },
            1600,
            1200,
        )

        point = registry.resolve_point(
            capture["screenshot_id"],
            800,
            600,
            windows=[
                {
                    "window_id": 42,
                    "bounds": {"x": 300, "y": 400, "width": 1000, "height": 500},
                    "pid": 7,
                    "title": "Example",
                }
            ],
        )

        self.assertEqual((point["x"], point["y"]), (800.0, 650.0))

    def test_expired_capture_is_rejected(self):
        now = [0]
        registry = mac_ui.CaptureRegistry(ttl_seconds=5, clock=lambda: now[0])
        capture = registry.register(
            {"logical_bounds": {"x": 0, "y": 0, "width": 100, "height": 100}},
            100,
            100,
        )
        now[0] = 6

        with self.assertRaisesRegex(mac_ui.UIError, "expired"):
            registry.get(capture["screenshot_id"])

    @mock.patch.object(host.mac_ui, "click")
    @mock.patch.object(host, "_window_list", return_value=[])
    def test_click_uses_resolved_screenshot_point(self, _windows, click):
        registry = mac_ui.CaptureRegistry()
        capture = registry.register(
            {"logical_bounds": {"x": 50, "y": 100, "width": 400, "height": 200}},
            800,
            400,
        )
        with mock.patch.object(host, "CAPTURES", registry):
            result = host.tool_click(
                {
                    "screenshot_id": capture["screenshot_id"],
                    "x": 200,
                    "y": 100,
                    "activate": False,
                }
            )

        click.assert_called_once_with(150.0, 150.0, button="left", clicks=1)
        self.assertEqual(result["global_point"], {"x": 150.0, "y": 150.0})


class McpImageTests(unittest.TestCase):
    def test_image_result_contains_native_image_and_metadata(self):
        result = protocol.mcp_image_result("YWJj", "image/png", {"target": "display"})

        self.assertEqual(
            result["content"][0],
            {"type": "image", "data": "YWJj", "mimeType": "image/png"},
        )
        self.assertEqual(result["content"][1]["type"], "text")

    @mock.patch.object(facade, "host_call")
    @mock.patch.object(facade, "host_health", return_value=True)
    def test_facade_converts_host_transport_payload(self, _health, host_call):
        host_call.return_value = {
            "_mcp_image": {"data": "YWJj", "mimeType": "image/png"},
            "metadata": {"target": "display", "ocr_lines": 1},
            "ocr_text": "Hello world",
        }

        result = facade.call_tool("token", "screenshot", {"target": "display"})

        self.assertEqual(result["content"][0]["type"], "image")
        self.assertEqual(result["content"][0]["data"], "YWJj")
        self.assertEqual(result["content"][2]["text"], "OCR text:\nHello world")


if __name__ == "__main__":
    unittest.main()

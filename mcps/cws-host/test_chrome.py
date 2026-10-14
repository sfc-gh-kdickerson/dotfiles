import json
import unittest
from unittest import mock

import chrome
import host


class ChromeTabTests(unittest.TestCase):
    @mock.patch.object(chrome, "_osascript")
    def test_lists_tabs_with_stable_ids_and_active_state(self, osascript):
        osascript.return_value = json.dumps(
            [
                {
                    "window_id": "12",
                    "active_tab_index": 2,
                    "tabs": [
                        {
                            "index": 1,
                            "title": "One",
                            "url": "https://example.com/one",
                            "loading": False,
                        },
                        {
                            "index": 2,
                            "title": "Two",
                            "url": "https://example.com/two",
                            "loading": True,
                        },
                    ],
                }
            ]
        )

        first = chrome.list_tabs()
        second = chrome.list_tabs()

        self.assertEqual(first[0]["tab_id"], second[0]["tab_id"])
        self.assertFalse(first[0]["active"])
        self.assertTrue(first[1]["active"])

    @mock.patch.object(chrome, "list_tabs")
    def test_resolve_tab_enforces_same_origin(self, list_tabs):
        list_tabs.return_value = [
            {
                "tab_id": "tab_one",
                "url": "https://example.com/page",
                "window_id": "1",
                "index": 1,
            }
        ]

        tab = chrome.resolve_tab(
            tab_id="tab_one", required_origin=("https", "example.com", 443)
        )

        self.assertEqual(tab["tab_id"], "tab_one")
        with self.assertRaisesRegex(chrome.ChromeError, "does not match"):
            chrome.resolve_tab(
                tab_id="tab_one", required_origin=("https", "other.example", 443)
            )


class ChromeJobTests(unittest.TestCase):
    @mock.patch.object(chrome, "_restore_active_tab")
    @mock.patch.object(chrome, "_set_active_tab", return_value={"previous_index": 1})
    @mock.patch.object(chrome, "_cleanup")
    @mock.patch.object(chrome, "_read_text_chunk")
    @mock.patch.object(chrome, "_wait")
    @mock.patch.object(chrome, "_start_eval")
    @mock.patch.object(chrome, "resolve_tab")
    def test_evaluate_waits_and_reassembles_json(
        self, resolve_tab, start, wait, read_chunk, cleanup, _set_active, restore
    ):
        tab = {"tab_id": "tab_one", "url": "https://example.com", "window_id": "1", "index": 1}
        resolve_tab.return_value = tab
        wait.return_value = {"status": "done", "kind": "json", "length": 12}
        read_chunk.return_value = '{"answer":42}'

        result = chrome.evaluate(
            tab_id="tab_one",
            source="Promise.resolve({answer: 42})",
            timeout=10,
        )

        self.assertEqual(result["value"], {"answer": 42})
        start.assert_called_once()
        wait.assert_called_once()
        cleanup.assert_called_once()
        restore.assert_called_once()

    @mock.patch.object(chrome, "_restore_active_tab")
    @mock.patch.object(chrome, "_set_active_tab", return_value={"previous_index": 1})
    @mock.patch.object(chrome, "_cleanup")
    @mock.patch.object(chrome, "_read_bytes_chunk")
    @mock.patch.object(chrome, "_wait")
    @mock.patch.object(chrome, "_start_fetch")
    @mock.patch.object(chrome, "list_tabs")
    def test_fetch_uses_open_same_origin_tab(
        self, list_tabs, start, wait, read_chunk, cleanup, _set_active, restore
    ):
        tab = {
            "tab_id": "tab_one",
            "url": "https://example.com/dashboard",
            "window_id": "1",
            "index": 1,
            "active": True,
        }
        list_tabs.return_value = [tab]
        wait.return_value = {
            "status": "done",
            "kind": "bytes",
            "length": 3,
            "metadata": {"status": 200, "content_type": "application/json"},
        }
        read_chunk.return_value = b"abc"

        result = chrome.fetch("https://example.com/api/data")

        self.assertEqual(result["body"], b"abc")
        self.assertEqual(result["metadata"]["status"], 200)
        start.assert_called_once()
        cleanup.assert_called_once()
        restore.assert_called_once()

    @mock.patch.object(chrome, "list_tabs", return_value=[])
    def test_fetch_requires_an_open_same_origin_tab(self, _list_tabs):
        with self.assertRaisesRegex(chrome.ChromeError, "open a Chrome tab"):
            chrome.fetch("https://example.com/api/data")


class ChromeHostToolTests(unittest.TestCase):
    @mock.patch.object(host, "_push_generated_bytes")
    @mock.patch.object(host.chrome_control, "evaluate")
    def test_large_eval_result_goes_to_cws(self, evaluate, push):
        evaluate.return_value = {
            "value": {"large": True},
            "serialized": '{"large":true}',
            "bytes": host.CHROME_INLINE_MAX + 1,
            "tab": {"tab_id": "tab_one"},
        }
        push.return_value = "/home/me/CWS-outbox/result.json"

        result = host.tool_chrome_eval(
            {"tab_id": "tab_one", "javascript": "({large: true})"}
        )

        self.assertEqual(result["remote_path"], "/home/me/CWS-outbox/result.json")
        self.assertNotIn("value", result)
        push.assert_called_once()

    @mock.patch.object(host, "_push_generated_bytes")
    @mock.patch.object(host.chrome_control, "fetch")
    def test_fetch_result_is_written_to_cws(self, fetch, push):
        fetch.return_value = {
            "body": b'{"ok":true}',
            "metadata": {
                "status": 200,
                "ok": True,
                "final_url": "https://example.com/api",
                "content_type": "application/json",
                "headers": {"content-type": "application/json"},
            },
            "tab": {"tab_id": "tab_one"},
        }
        push.return_value = "/home/me/CWS-outbox/api"

        result = host.tool_chrome_fetch({"url": "https://example.com/api"})

        self.assertEqual(result["remote_path"], "/home/me/CWS-outbox/api")
        self.assertEqual(result["bytes"], 11)
        self.assertEqual(result["status"], 200)


if __name__ == "__main__":
    unittest.main()

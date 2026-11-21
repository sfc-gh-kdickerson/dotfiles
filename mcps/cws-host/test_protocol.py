import os
import tempfile
import unittest

import protocol


class TomlTableKeysTests(unittest.TestCase):
    def test_bare_and_quoted_keys(self):
        self.assertEqual(
            protocol._toml_table_keys("mcp_servers.mac-host.http_headers"),
            ["mcp_servers", "mac-host", "http_headers"],
        )
        self.assertEqual(
            protocol._toml_table_keys('mcp_servers."mac-host"'),
            ["mcp_servers", "mac-host"],
        )
        self.assertEqual(
            protocol._toml_table_keys('["mcp_servers"."mac-host"]'),
            ["mcp_servers", "mac-host"],
        )

    def test_does_not_match_similar_server_names(self):
        self.assertFalse(
            protocol._is_mac_host_mcp_table("mcp_servers.mac-host-backup")
        )
        self.assertTrue(protocol._is_mac_host_mcp_table("mcp_servers.mac-host"))
        self.assertTrue(
            protocol._is_mac_host_mcp_table("mcp_servers.mac-host.http_headers")
        )


class CodexUpsertTests(unittest.TestCase):
    def test_creates_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.toml")
            protocol.upsert_codex_mac_host_mcp(
                path, "http://127.0.0.1:18765/mcp", "abc123"
            )
            with open(path) as fh:
                text = fh.read()
            self.assertIn("[mcp_servers.mac-host]\n", text)
            self.assertIn('url = "http://127.0.0.1:18765/mcp"\n', text)
            self.assertIn('Authorization = "Bearer abc123"\n', text)

    def test_preserves_other_servers_and_replaces_mac_host(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.toml")
            with open(path, "w") as fh:
                fh.write(
                    "model = \"gpt-5\"\n"
                    "\n"
                    "[mcp_servers.glean]\n"
                    'command = "sf"\n'
                    "\n"
                    "[mcp_servers.mac-host]\n"
                    'url = "http://old"\n'
                    "\n"
                    "[mcp_servers.mac-host.http_headers]\n"
                    'Authorization = "Bearer old"\n'
                    "\n"
                    "[mcp_servers.jenkins]\n"
                    'command = "jenkins"\n'
                )
            protocol.upsert_codex_mac_host_mcp(
                path, "http://127.0.0.1:18765/mcp", "newtoken"
            )
            with open(path) as fh:
                text = fh.read()
            self.assertIn("model = \"gpt-5\"\n", text)
            self.assertIn("[mcp_servers.glean]\n", text)
            self.assertIn("[mcp_servers.jenkins]\n", text)
            self.assertIn('url = "http://127.0.0.1:18765/mcp"\n', text)
            self.assertIn('Authorization = "Bearer newtoken"\n', text)
            self.assertNotIn("http://old", text)
            self.assertNotIn("Bearer old", text)
            self.assertEqual(text.count("[mcp_servers.mac-host]"), 1)


if __name__ == "__main__":
    unittest.main()

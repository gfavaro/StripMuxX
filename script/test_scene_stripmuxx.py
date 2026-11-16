import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "resources" / "scene-stripmuxx.sh"


class SceneHookTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.config = self.dir / "stripmuxx.toml"
        self.saved = Path(str(self.config) + ".before-scene")
        self.reloads = self.dir / "reloads"
        self.cli = self.dir / "cli"
        self.cli.write_text(f'#!/bin/sh\necho "$@" >> "{self.reloads}"\n')
        self.cli.chmod(0o755)

    def run_hook(self, event="apply", accent="#205ea6"):
        env = dict(os.environ, STRIPMUXX_CONFIG=str(self.config), STRIPMUXX_CLI=str(self.cli), SCENE_EVENT=event)
        if accent is not None:
            env["SCENE_ACCENT"] = accent
        return subprocess.run(["sh", str(SCRIPT)], env=env, capture_output=True, text=True)

    def text(self):
        return self.config.read_text()

    def test_adds_the_key_at_the_top_when_there_is_none(self):
        self.config.write_text("config-version = 2\n[gaps]\ninner.horizontal = 8\n")
        self.assertEqual(self.run_hook().returncode, 0)
        self.assertEqual(self.text(), "accent-color = '#205ea6'\nconfig-version = 2\n[gaps]\ninner.horizontal = 8\n")
        self.assertEqual(self.saved.read_text(), "accent-color=\n")
        self.assertEqual(self.reloads.read_text(), "reload-config\n")

    def test_replaces_an_existing_root_key_and_keeps_the_rest(self):
        self.config.write_text("scrolling.edge-preview = 0\naccent-color = '#7AA2F7' # mine\nfullscreen = 1\n")
        self.run_hook(accent="#4385be")
        self.assertEqual(self.text(), "scrolling.edge-preview = 0\naccent-color = '#4385be'\nfullscreen = 1\n")
        self.assertEqual(self.saved.read_text(), "accent-color=#7AA2F7\n")

    def test_a_double_quoted_value_is_saved_and_replaced(self):
        self.config.write_text('accent-color = "#7AA2F7"\n')
        self.run_hook()
        self.assertEqual(self.text(), "accent-color = '#205ea6'\n")
        self.assertEqual(self.saved.read_text(), "accent-color=#7AA2F7\n")

    def test_a_key_inside_a_table_is_not_the_root_accent(self):
        self.config.write_text("[mode.main]\naccent-color = 'x'\n")
        self.run_hook()
        self.assertTrue(self.text().startswith("accent-color = '#205ea6'\n"))
        self.assertIn("[mode.main]\naccent-color = 'x'\n", self.text())

    def test_applying_again_keeps_the_first_saved_value(self):
        self.config.write_text("accent-color = '#111111'\n")
        self.run_hook(accent="#222222")
        self.run_hook(accent="#333333")
        self.assertEqual(self.text(), "accent-color = '#333333'\n")
        self.assertEqual(self.saved.read_text(), "accent-color=#111111\n")

    def test_restore_puts_back_the_original_value(self):
        self.config.write_text("accent-color = '#111111'\nother = 1\n")
        self.run_hook(accent="#222222")
        self.run_hook(event="restore", accent=None)
        self.assertEqual(self.text(), "accent-color = '#111111'\nother = 1\n")
        self.assertFalse(self.saved.exists())

    def test_restore_removes_the_key_when_there_was_none(self):
        original = "scrolling.edge-preview = 0\n[gaps]\ninner.horizontal = 8\n"
        self.config.write_text(original)
        self.run_hook()
        self.run_hook(event="restore", accent=None)
        self.assertEqual(self.text(), original)
        self.assertFalse(self.saved.exists())

    def test_restore_without_a_saved_value_changes_nothing(self):
        self.config.write_text("accent-color = '#111111'\n")
        self.run_hook(event="restore", accent=None)
        self.assertEqual(self.text(), "accent-color = '#111111'\n")

    def test_rejects_anything_but_a_plain_hex_color(self):
        self.config.write_text("a = 1\n")
        for bad in ["", "205ea6", "#205ea", "#205ea6ff", "#zzzzzz", "red", "#205ea6'; rm -rf /"]:
            self.run_hook(accent=bad)
            self.assertEqual(self.text(), "a = 1\n", bad)
        self.assertFalse(self.saved.exists())
        self.assertFalse(self.reloads.exists())

    def test_a_missing_config_is_not_an_error_and_is_not_created(self):
        self.assertEqual(self.run_hook().returncode, 0)
        self.assertFalse(self.config.exists())

    def test_a_missing_cli_does_not_fail_the_hook(self):
        self.config.write_text("a = 1\n")
        self.cli.unlink()
        self.assertEqual(self.run_hook().returncode, 0)
        self.assertIn("accent-color = '#205ea6'", self.text())


if __name__ == "__main__":
    unittest.main()

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "resources/default-config.toml"
PRESET = ROOT / "resources/shortcut-presets/ergonomic-default.toml"


def bindings(path):
    text = path.read_text()
    section = text.split("[mode.main.binding]", 1)[1].split("\n[", 1)[0]
    return dict(re.findall(r"^\s+([A-Za-z0-9-]+)\s*=\s*'([^']+)'", section, flags=re.M))


class ErgonomicShortcutPresetTest(unittest.TestCase):
    def test_every_default_action_is_preserved(self):
        self.assertEqual(sorted(bindings(REFERENCE).values()), sorted(bindings(PRESET).values()))
        self.assertEqual(len(bindings(REFERENCE)), len(bindings(PRESET)))

    def test_avoids_plain_option_letter_chords(self):
        keys = list(bindings(PRESET))
        self.assertFalse(any(re.fullmatch(r"alt-[a-z]", k) for k in keys))

    def test_navigation_is_consistent(self):
        b = bindings(PRESET)
        self.assertEqual(b["ctrl-alt-h"], "focus left")
        self.assertEqual(b["ctrl-alt-l"], "focus right")
        self.assertEqual(b["ctrl-alt-shift-h"], "move left")
        self.assertEqual(b["ctrl-alt-s"], "scrolling-minimap")
        self.assertEqual(b["ctrl-alt-r"], "scrolling-width next")
        self.assertEqual(b["ctrl-alt-shift-r"], "scrolling-width previous")

    def test_preserves_reference_non_shortcut_configuration(self):
        def without_bindings(text):
            return re.sub(r"\[mode.main.binding\][\s\S]*?(?=\n\[|\Z)", "[mode.main.binding]", text)
        original = without_bindings(REFERENCE.read_text())
        variant = without_bindings(PRESET.read_text())
        self.assertEqual(original, variant[variant.index(original[:80]):])

if __name__ == "__main__":
    unittest.main()

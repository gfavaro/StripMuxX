"""Guard fork-specific isolation when integrating upstream updates."""
import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ForkIdentityTests(unittest.TestCase):
    def test_plist_has_no_upstream_update_feed_or_key(self):
        with (ROOT / "resources/WinMux-Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertNotIn("SUEnableAutomaticChecks", info)
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)

    def test_project_generates_only_fork_bundle_identifiers(self):
        project = (ROOT / "project.yml").read_text()
        package = (ROOT / "Package.swift").read_text()
        self.assertIn('executable(name: "stripmuxx", targets: ["Cli"])', package)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.gfavaro.stripmuxx\n", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.gfavaro.stripmuxx.debug\n", project)
        self.assertNotIn("com.zimengxiong", project)
        self.assertNotIn("SUFeedURL", project)
        self.assertNotIn("SUPublicEDKey", project)

    def test_release_has_no_updater(self):
        package = (ROOT / "Package.swift").read_text()
        self.assertNotIn("Sparkle", package)
        self.assertFalse((ROOT / "Sources/SparkleSupport").exists())

    def test_fork_does_not_delete_upstream_login_items(self):
        login = (ROOT / "Sources/AppBundle/config/startAtLogin.swift").read_text()
        self.assertNotIn("removeItem", login)

    def test_cli_name_cannot_overwrite_app_on_case_insensitive_volumes(self):
        build = (ROOT / "script/fork-build.sh").read_text()
        self.assertIn('"$fork_app/Contents/MacOS/stripmuxx-cli"', build)
        self.assertIn('"$fork_bin/stripmuxx"', build)
        self.assertNotIn('"$fork_app/Contents/MacOS/stripmuxx"', build)
        self.assertNotEqual("StripMuxX".casefold(), "stripmuxx-cli".casefold())

    def test_fork_build_accepts_a_persistent_local_signing_identity(self):
        build = (ROOT / "script/fork-build.sh").read_text()
        self.assertIn('"${CODESIGN_IDENTITY:-}"', build)
        self.assertIn("for fork_config_dir in stripmuxx winmux-gf; do", build)
        self.assertIn("$fork_config_dir/signing-identity", build)
        self.assertIn('codesign --force --deep --sign "$fork_signing_identity"', build)


class AppIconTest(unittest.TestCase):
    """The app icon reaches the built app only if the project names the set and every slot is filled."""

    def test_project_names_the_app_icon_set(self):
        project = (ROOT / "project.yml").read_text()
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon", project)

    def test_every_slot_of_the_icon_set_has_a_png_of_the_declared_size(self):
        import json
        import struct
        folder = ROOT / "resources/Assets.xcassets/AppIcon.appiconset"
        images = json.loads((folder / "Contents.json").read_text())["images"]
        self.assertEqual(len(images), 10)
        for image in images:
            points = int(image["size"].split("x")[0])
            scale = int(image["scale"].rstrip("x"))
            data = (folder / image["filename"]).read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n", image["filename"])
            width, height = struct.unpack(">II", data[16:24])
            self.assertEqual((width, height), (points * scale, points * scale), image["filename"])


if __name__ == "__main__":
    unittest.main()

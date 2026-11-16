"""Guard fork-specific isolation when integrating upstream updates."""
import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ForkIdentityTests(unittest.TestCase):
    def test_plist_has_no_upstream_update_feed_or_key(self):
        with (ROOT / "resources/WinMux-Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertFalse(info["SUEnableAutomaticChecks"])
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


if __name__ == "__main__":
    unittest.main()

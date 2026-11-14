@testable import AppBundle
import Foundation
import Common
import XCTest

@MainActor
final class ConfigurationSourceTest: WorkspaceTestCase {
    private func fixture(_ text: String) throws -> (URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "StripMuxX.ConfigurationSourceTest." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let file = directory.appending(path: "config.toml")
        try text.write(to: file, atomically: true, encoding: .utf8)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try FileManager.default.removeItem(at: directory)
        }
        return (file, defaults)
    }

    func testMinimumMigrationPreservesSparseNamesAndFillsExplicitSlots() throws {
        let original = """
        # User config
        config-version = 2
        persistent-workspaces = ['7', 'Code']
        minimum-workspace-count = 5
        [mode.main.binding]
        alt-j = 'focus dfs-next'
        """
        let migrated = try migratingLegacyMinimumWorkspaceCount(in: original)
        XCTAssertFalse(migrated.contains("minimum-workspace-count"))
        XCTAssertTrue(migrated.contains("# User config"))
        let parsed = parseConfig(migrated)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(Array(parsed.config.persistentWorkspaces), ["7", "Code", "1", "2", "3"])
        XCTAssertEqual(try migratingLegacyMinimumWorkspaceCount(in: migrated), migrated)
        XCTAssertEqual(Array(parseConfig(original).config.persistentWorkspaces), ["7", "Code", "1", "2", "3"])
    }

    func testSmallerMinimumDoesNotRewriteExplicitNamesOrComments() throws {
        let original = """
        config-version = 2
        persistent-workspaces = [
          '7', # primary task
          'Code'
        ]
        minimum-workspace-count = 1
        """
        let migrated = try migratingLegacyMinimumWorkspaceCount(in: original)
        XCTAssertTrue(migrated.contains("# primary task"))
        XCTAssertEqual(Array(parseConfig(migrated).config.persistentWorkspaces), ["7", "Code"])
    }

    func testLegacyVersionOneBindingsSurviveUpgrade() throws {
        let migrated = try migratingLegacyMinimumWorkspaceCount(in: """
        minimum-workspace-count = 3
        [mode.main.binding]
        alt-7 = 'workspace 7'
        """)
        let parsed = parseConfig(migrated)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.configVersion, 2)
        XCTAssertEqual(Array(parsed.config.persistentWorkspaces), ["1", "2", "3"], "Shortcuts are not persistent desktops")
        XCTAssertFalse(parsed.config.modes[mainModeId]?.bindings.isEmpty ?? true)
    }

    func testQuotedMinimumKeysMigrateWithoutRecursion() throws {
        for key in [#""minimum-workspace-count""#, #""minimum-workspace-\u0063ount""#] {
            let migrated = try migratingLegacyMinimumWorkspaceCount(in: key + " = 2")
            XCTAssertEqual(Array(parseConfig(migrated).config.persistentWorkspaces), ["1", "2"])
        }
    }

    func testInvalidLegacyMinimumCannotSilentlyChangeConfig() {
        for value in ["-1", "true", "'3'", "1.5", String(Int.max)] {
            XCTAssertThrowsError(try migratingLegacyMinimumWorkspaceCount(in: "minimum-workspace-count = \(value)"))
        }
    }

    func testLegacyMenuBarPreferencesMoveIntoTOMLOnce() throws {
        let (file, defaults) = try fixture("config-version = 2\n")
        defaults.set("workspace", forKey: "menuBarIndicator")
        defaults.set("monochrome", forKey: "iconAppearance")
        try migrateLegacyConfiguration(at: file, defaults: defaults)
        let config = parseConfig(try String(contentsOf: file, encoding: .utf8)).config
        XCTAssertEqual(config.menuBar.indicator, .workspace)
        XCTAssertEqual(config.menuBar.iconAppearance, .monochrome)
        XCTAssertNil(defaults.string(forKey: "menuBarIndicator"), "A later TOML edit must win")
    }

    func testFailedMigrationPreservesOriginalAndLegacyPreferences() throws {
        let original = "config-version = 2\nunknown-key = true\n"
        let (file, defaults) = try fixture(original)
        defaults.set("workspace", forKey: "menuBarIndicator")
        XCTAssertThrowsError(try migrateLegacyConfiguration(at: file, defaults: defaults))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original)
        XCTAssertEqual(defaults.string(forKey: "menuBarIndicator"), "workspace")
    }

}

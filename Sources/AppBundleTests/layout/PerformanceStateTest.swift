@testable import AppBundle
import AppKit
import XCTest

@MainActor final class PerformanceStateTest: XCTestCase {
    func testMinimumSizesSurviveNewStoreAndReset() throws {
        let suite = "StripMuxX.PerformanceTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistedAppMinimums(defaults: defaults)
        store.remember(CGSize(width: 640, height: 0), for: "test.app")
        let reopened = PersistedAppMinimums(defaults: defaults)
        XCTAssertEqual(reopened.size(for: "test.app"), CGSize(width: 640, height: 0))
        reopened.remember(.zero, for: "test.app")
        XCTAssertNil(PersistedAppMinimums(defaults: defaults).size(for: "test.app"))
        reopened.remember(CGSize(width: 200, height: 200), for: "test.app")
        reopened.reset()
        XCTAssertTrue(PersistedAppMinimums(defaults: defaults).isEmpty)
    }

    func testMinimumStoreRejectsInvalidEvidence() throws {
        let suite = "StripMuxX.PerformanceTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PersistedAppMinimums(defaults: defaults)
        store.remember(CGSize(width: -1, height: 20), for: "bad")
        store.remember(CGSize(width: CGFloat.nan, height: 20), for: "bad")
        XCTAssertNil(store.size(for: "bad"))
    }

    func testOldMinimumEvidenceDoesNotSurviveMigrationOrFrozenRestoration() throws {
        let suite = "StripMuxX.MinimumMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["test.app": [900.0, 800.0]], forKey: "confirmedAppMinimumSizes.v1")
        XCTAssertNil(PersistedAppMinimums(defaults: defaults).size(for: "test.app"))
        XCTAssertNil(defaults.object(forKey: "confirmedAppMinimumSizes.v1"))
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let window = TestWindow.new(id: 99010, parent: focus.workspace.rootTilingContainer)
        let encoded = try JSONEncoder().encode(FrozenWindow(window))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "minimumEvidenceVersion")
        legacy["learnedMinimumSize"] = [900.0, 800.0]
        let restored = try JSONDecoder().decode(FrozenWindow.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.learnedMinimumSize)
        legacy["minimumEvidenceVersion"] = 2
        let current = try JSONDecoder().decode(FrozenWindow.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(current.learnedMinimumSize, CGSize(width: 900, height: 800))
    }

}

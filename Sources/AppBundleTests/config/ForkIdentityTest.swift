@testable import AppBundle
import Common
import XCTest

final class ForkIdentityTest: XCTestCase {
    func testForkIdentityDoesNotUseUpstreamSocketOrState() {
        XCTAssertEqual(stableWinMuxAppId, "com.gfavaro.stripmuxx")
        XCTAssertTrue(winMuxAppId.hasPrefix(stableWinMuxAppId))
        XCTAssertTrue(winMuxAppName.hasPrefix("StripMuxX"))
        XCTAssertTrue(socketPath.contains(winMuxAppId))
        XCTAssertFalse(socketPath.contains("com.zimengxiong"))
        XCTAssertEqual(forkRepositoryURL, "https://github.com/gfavaro/StripMuxX")
    }

    func testForkConfigurationHasAnIndependentOwnedDirectory() {
        XCTAssertEqual(generatedConfigDirectoryName, "stripmuxx")
        XCTAssertEqual(generatedConfigFileName, "stripmuxx.toml")
        XCTAssertEqual(generatedConfigUrl().deletingLastPathComponent().lastPathComponent, "stripmuxx")
    }

    func testAppStateHasItsOwnDirectory() {
        XCTAssertEqual(winMuxAppSupportDirectoryName, "StripMuxX")
    }
}

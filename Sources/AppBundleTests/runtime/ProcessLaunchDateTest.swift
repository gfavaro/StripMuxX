import AppKit
import NativeSpaces
import XCTest

final class ProcessLaunchDateTest: XCTestCase {
    func testEveryProcessHasALaunchDateEvenWithoutAppKitOne() throws {
        // Finder's AppKit launch date is nil; without one, no window of it could be written.
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        let apps = NSWorkspace.shared.runningApplications + finder
        for app in apps where !app.isTerminated {
            let date = try XCTUnwrap(app.processLaunchDate, "\(app.bundleIdentifier ?? "\(app.processIdentifier)")")
            XCTAssertLessThanOrEqual(date, Date())
            if let appKit = app.launchDate { XCTAssertEqual(date, appKit) }
        }
        XCTAssertEqual(NSRunningApplication.current.processLaunchDate, NSRunningApplication.current.processLaunchDate)
    }
}

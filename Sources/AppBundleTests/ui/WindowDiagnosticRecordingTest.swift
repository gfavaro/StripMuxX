@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WindowDiagnosticRecordingTest: WorkspaceTestCase {
    override func tearDown() async throws {
        _ = finishWindowDebugRecording()
        try await super.tearDown()
    }

    func testCancelledSnapshotDoesNotBecomeARecordedFailure() async throws {
        TrayMenuModel.shared.isEnabled = true
        _ = TestWindow.new(id: 99103, parent: focus.workspace.rootTilingContainer).focusWindow()
        _ = try await DebugWindowsCommand(args: DebugWindowsCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        let target = TestWindow.new(id: 99104, parent: focus.workspace.rootTilingContainer)
        do {
            try await debugWindowsIfRecording(target) { _ in throw CancellationError() }
            XCTFail("Cancellation must propagate")
        } catch is CancellationError { }
        try await debugWindowsIfRecording(target) { _ in "second capture succeeded" }
        XCTAssertTrue(finishWindowDebugRecording().contains("second capture succeeded"))
    }
}

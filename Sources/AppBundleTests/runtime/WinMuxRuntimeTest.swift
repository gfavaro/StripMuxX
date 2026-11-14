@testable import AppBundle
import Common
import AppKit
import HotKey
import XCTest

@MainActor
final class WinMuxRuntimeTest: WorkspaceTestCase {
    private func world() -> WinMuxRuntime {
        var value = defaultConfig
        value.persistentWorkspaces = []
        value.modes = [mainModeId: Mode(bindings: [:], tapBindings: [:])]
        value.onFocusChanged = []
        value.onFocusedMonitorChanged = []
        value.execOnWorkspaceChange = []
        return WinMuxRuntime(config: value)
    }

    private func display(_ index: Int, x: CGFloat) -> TestMonitor {
        let rect = Rect(topLeftX: x, topLeftY: 0, width: 1920, height: 1080)
        return TestMonitor(monitorAppKitNsScreenScreensId: index, name: "Display \(index)",
                           rect: rect, visibleRect: rect, isMain: index == 1)
    }

    func testNestedBindingRestoresOwnerAfterThrowAndSuspension() async {
        enum Failure: Error { case expected }
        let original = runtime, first = world(), second = world()
        await first.withValue {
            XCTAssertTrue(runtime === first)
            do {
                try await second.withValue {
                    await Task.yield()
                    XCTAssertTrue(runtime === second)
                    throw Failure.expected
                }
                XCTFail("Expected failure")
            } catch { }
            XCTAssertTrue(runtime === first)
        }
        XCTAssertTrue(runtime === original)
    }

    func testDisplayOverridesAndSortedCacheBelongToOwnerAndInvalidateTogether() {
        let first = world(), second = world()
        first.withValue {
            setMonitorsForTests([display(1, x: 1920), display(2, x: 0)])
            XCTAssertEqual(sortedMonitors.map(\.name), ["Display 2", "Display 1"])
            XCTAssertEqual(mainMonitor.name, "Display 1")
        }
        second.withValue { XCTAssertEqual(monitors.map(\.name), ["Test Monitor"]) }
        first.withValue {
            setMonitorsForTests([display(1, x: 0), display(2, x: 1920)])
            XCTAssertEqual(sortedMonitors.map(\.name), ["Display 1", "Display 2"])
            runtime.displays.invalidate()
            XCTAssertEqual(sortedMonitors.map(\.name), ["Display 1", "Display 2"])
        }
    }

    func testScreenNotificationInvalidatesAllOwnedMonitorCaches() {
        let notifications = NotificationCenter()
        var snapshots: [Monitor] = [display(1, x: 0), display(2, x: 1920)]
        var listReads = 0, mainReads = 0
        weak var released: MonitorState?
        do {
            let state = MonitorState(readMonitors: { listReads += 1; return snapshots },
                                     readMain: { mainReads += 1; return snapshots[0] },
                                     notifications: notifications, observeChanges: true)
            released = state
            for _ in 0..<20 {
                XCTAssertEqual(state.all().count, 2)
                XCTAssertEqual(state.sorted().first?.name, "Display 1")
                XCTAssertEqual(state.main().rect.minX, 0)
            }
            XCTAssertEqual(listReads, 1)
            XCTAssertEqual(mainReads, 1)
            snapshots = [display(1, x: 1920), display(2, x: 0)]
            notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            XCTAssertEqual(state.sorted().first?.name, "Display 2")
            XCTAssertEqual(state.main().rect.minX, 1920)
            XCTAssertEqual(listReads, 2)
            XCTAssertEqual(mainReads, 2)
        }
        XCTAssertNil(released)
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertEqual(listReads, 2)
        XCTAssertEqual(mainReads, 2)
    }

    func testMonitorFrameNormalizationSupportsDisplaysAboveAndBelowMain() {
        XCTAssertEqual(CGRect(x: 0, y: 0, width: 1920, height: 1080)
            .monitorFrameNormalized(mainHeight: 1080).topLeftCorner, .zero)
        XCTAssertEqual(CGRect(x: -2560, y: 1080, width: 2560, height: 1440)
            .monitorFrameNormalized(mainHeight: 1080).topLeftCorner, CGPoint(x: -2560, y: -1440))
        XCTAssertEqual(CGRect(x: 1920, y: -1440, width: 2560, height: 1440)
            .monitorFrameNormalized(mainHeight: 1080).topLeftCorner, CGPoint(x: 1920, y: 1080))
    }

    func testModeAndSequenceStateDoNotLeakToAnotherOwner() {
        let first = world(), second = world()
        first.withValue {
            activeMode = "custom"
            sequenceBindingsPrefixKeys = [.escape]
            noteSequencePrefixKeyPressed(.escape)
            setHotkeysSuspended(true)
        }
        second.withValue {
            XCTAssertEqual(activeMode, mainModeId)
            XCTAssertTrue(sequenceBindingsPrefixKeys.isEmpty)
            XCTAssertNil(runtime.hotkeys.lastSequencePrefixKey)
            XCTAssertFalse(runtime.hotkeys.hotkeysSuspended)
        }
        first.withValue { XCTAssertEqual(activeMode, "custom") }
    }

    func testReloadGatesDoNotBlockIndependentOwners() async {
        let first = world(), second = world()
        await first.configuration.reloadGate.acquire()
        defer { first.configuration.reloadGate.release() }
        let completed = expectation(description: "independent gate available")
        let task = Task { @MainActor in
            await second.configuration.reloadGate.acquire()
            second.configuration.reloadGate.release()
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
        await task.value
    }

    func testScopedOwnerReleasesAfterUse() {
        weak var observed: WinMuxRuntime?
        do {
            let owner = world()
            observed = owner
            owner.withValue {
                _ = Workspace.get(byName: "1")
                setMonitorsForTests([display(1, x: 0)])
                _ = sortedMonitors
                _ = focus
            }
        }
        XCTAssertNil(observed)
    }
}

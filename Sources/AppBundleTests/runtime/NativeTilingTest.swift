import AppKit
import Common
import XCTest
@testable import AppBundle
@testable import NativeSpaces

@MainActor
final class NativeTilingTest: WorkspaceTestCase {
    private func nativeWorkspace() -> Workspace {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let display = TestMonitor(displayUUID: "display-a", monitorAppKitNsScreenScreensId: 1,
            name: "fixture", rect: rect, visibleRect: rect, isMain: true)
        setMonitorsForTests([display])
        let snapshot = NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a",
            activeSpaceID: "1", spaces: [NativeSpace(id: "1", uuid: "desktop-a", type: 0)])],
            windows: (1...6).map { NativeWindowMembership(windowID: UInt32($0), spaceIDs: ["1"]) },
            readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
        runtime.native.layouts.reconcile(inventory, displays: [display])
        return runtime.native.layouts.activeWorkspace(on: "display-a")!
    }

    func testFrameDiagnosticsIdentifyRetainedWindowsWithoutClaimingActualAXFrames() async throws {
        let workspace = nativeWorkspace()
        let visible = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let concealed = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        concealed.nativeLayoutEligible = false
        TestWindow.new(id: 3, parent: workspace)
        try await workspace.layoutWorkspace()
        let rows = nativeWindowFrameDiagnostics(runtime.native.layouts)
        XCTAssertEqual(rows.map(\.windowID), [1, 2, 3])
        XCTAssertEqual(rows.map(\.spaceUUID), ["desktop-a", "desktop-a", "desktop-a"])
        XCTAssertEqual(rows.map(\.eligible), [true, false, true])
        XCTAssertNotNil(rows[0].desiredFrame)
        XCTAssertNil(rows[1].desiredFrame)
        XCTAssertTrue(rows[2].floating)
        XCTAssertNil(rows[2].desiredFrame)
        XCTAssertTrue(visible.nodeWorkspace === workspace)
    }

    func testQueuedCommandCannotFollowFocusToAnotherWorkspaceOrWindow() throws {
        let workspace = nativeWorkspace()
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        let command = try XCTUnwrap(parseCommand("resize width +20").unwrap().0)
        let layouts = runtime.native.layouts
        let initial = focus
        let target = try XCTUnwrap(NativeCommandTargetFence([command], env: .defaultEnv, defaultFocus: initial, layouts: layouts))
        XCTAssertTrue(target.matches(layouts, defaultFocus: initial))
        _ = second.focusWindow()
        XCTAssertFalse(target.matches(layouts, defaultFocus: focus))
        XCTAssertTrue(target.matches(layouts, defaultFocus: focus, allowDefaultFocusChanges: true))
        let other = Workspace.get(byName: "other-desktop")
        XCTAssertFalse(target.matches(layouts, defaultFocus: LiveFocus(windowOrNil: nil, workspace: other)))
        let explicitCommand = try XCTUnwrap(parseCommand("resize --window-id 1 width +20").unwrap().0)
        let explicit = try XCTUnwrap(NativeCommandTargetFence([explicitCommand], env: .defaultEnv,
            defaultFocus: initial, layouts: layouts))
        XCTAssertTrue(explicit.matches(layouts, defaultFocus: focus)) // Explicit target is independent of app focus.
        first.bind(to: other.rootTilingContainer, adaptiveWeight: 1, index: 0)
        XCTAssertFalse(explicit.matches(layouts, defaultFocus: focus))
        first.unbindFromParent()
        TestApp.shared._windows.removeAll { $0 === first }
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        XCTAssertFalse(explicit.matches(layouts, defaultFocus: focus)) // Reused IDs cannot inherit a queued command.
        XCTAssertTrue(second.nodeWorkspace === workspace)
    }

    func testFloatingToTilingCannotBindAfterItsNativeReadWasInvalidated() async throws {
        let workspace = nativeWorkspace()
        let window = TestWindow.new(id: 1, parent: workspace)
        _ = window.focusWindow()
        let layouts = runtime.native.layouts
        defer { window.sizeReader = nil }
        window.sizeReader = {
            await Task.yield()
            var stopped = NativeWorkspaceInventory()
            stopped.stop()
            layouts.reconcile(stopped, displays: [mainMonitor])
            return CGSize(width: 500, height: 400)
        }
        let result = try await NativeTilingCommandScope.$active.withValue(true) {
            try await parseCommand("layout tiling").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.joined().contains("changed"))
        XCTAssertTrue(window.parent === workspace)
    }

    func testQueuedCommandIsRevokedByObservedNativeSpaceSwitch() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        _ = window.focusWindow()
        let layouts = runtime.native.layouts
        let command = try XCTUnwrap(parseCommand("resize width +20").unwrap().0)
        let target = try XCTUnwrap(NativeCommandTargetFence([command], env: .defaultEnv,
            defaultFocus: focus, layouts: layouts))
        let next = NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "2",
            spaces: [NativeSpace(id: "1", uuid: "desktop-a", type: 0), NativeSpace(id: "2", uuid: "desktop-b", type: 0)])],
            windows: [NativeWindowMembership(windowID: 1, spaceIDs: ["1"])], readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(next, for: inventory.invalidate()))
        layouts.reconcile(inventory, displays: [mainMonitor])
        let incoming = try XCTUnwrap(layouts.activeWorkspace(on: "display-a"))
        XCTAssertFalse(target.matches(layouts, defaultFocus: incoming.toLiveFocus(), allowDefaultFocusChanges: true))
        XCTAssertTrue(layouts.retainedByUUID["desktop-a"] === workspace)
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertTrue(window.parent === root)
        XCTAssertNil(window.lastAppliedLayoutPhysicalRect)
    }

    func testCommandSequenceRejectsRevokedNativeTargetBeforeMutation() async throws {
        let workspace = nativeWorkspace()
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()
        let root = workspace.rootTilingContainer
        let result = try await NativeTilingCommandScope.$validateTarget.withValue({ false }) {
            try await NativeTilingCommandScope.$active.withValue(true) {
                try await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            }
        }
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.joined().contains("target changed"))
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertTrue(root.children.first === window)
    }

    func testIncomingSpaceReadPreservesUnqueriedDisplaysAndRetiresOutgoingPresentation() throws {
        let displays = (0..<3).map { index -> TestMonitor in
            let rect = Rect(topLeftX: CGFloat(index * 1920), topLeftY: 0, width: 1920, height: 1080)
            return TestMonitor(displayUUID: "display-\(index)", monitorAppKitNsScreenScreensId: index + 1,
                name: "fixture", rect: rect, visibleRect: rect, isMain: index == 0)
        }
        setMonitorsForTests(displays)
        func snapshot(active: String, partial: Bool) -> NativeSpacesSnapshot {
            NativeSpacesSnapshot(displays: (0..<3).map { index in
                NativeSpaceDisplay(identifier: "display-\(index)", activeSpaceID: index == 0 ? active : "\(index + 1)",
                    spaces: (index == 0 ? ["1", "4"] : ["\(index + 1)"]).map { NativeSpace(id: $0, uuid: "desktop-\($0)", type: 0) })
            }, windows: (partial ? [4] : [1, 2, 3, 4]).map {
                NativeWindowMembership(windowID: UInt32($0), spaceIDs: ["\($0)"])
            }, readMilliseconds: 0, capturedAt: .now, reconciliationSpaceIDs: partial ? ["4"] : nil)
        }
        func publish(_ snapshot: NativeSpacesSnapshot) {
            var inventory = NativeWorkspaceInventory()
            XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
            runtime.native.layouts.reconcile(inventory, displays: displays)
        }
        let layouts = runtime.native.layouts
        publish(snapshot(active: "1", partial: false))
        let windows = try (1...4).map { id in
            TestWindow.new(id: UInt32(id), parent: try XCTUnwrap(layouts.currentBySpaceID["\(id)"]).rootTilingContainer)
        }
        let roots = windows.map(\.parent)
        publish(snapshot(active: "4", partial: true))
        NativeWindowReconciler.updateEligibility(snapshot(active: "4", partial: true), windows: windows,
            ownerPIDs: [4: TestApp.shared.pid], layouts: layouts)
        XCTAssertFalse(windows[0].nativeLayoutEligible)
        XCTAssertTrue(windows[1].nativeLayoutEligible)
        XCTAssertTrue(windows[2].nativeLayoutEligible)
        XCTAssertTrue(windows[3].nativeLayoutEligible)
        for index in windows.indices { XCTAssertTrue(windows[index].parent === roots[index]) }
        // Retained presentation is not fresh membership or frame authority.
        XCTAssertNil(layouts.registration(for: 2))
        XCTAssertNil(layouts.registration(for: 3))
        XCTAssertNotNil(layouts.registration(for: 4))
    }

    func testSharedLayoutDoesNotWriteIneligibleWindowAndPreservesFloatingFrame() async throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let visible = TestWindow.new(id: 1, parent: root)
        let hidden = TestWindow.new(id: 2, parent: root)
        hidden.nativeLayoutEligible = false
        let original = Rect(topLeftX: 20, topLeftY: 50, width: 300, height: 400)
        let floating = TestWindow.new(id: 3, parent: workspace, rect: original)
        try await workspace.layoutWorkspace()
        XCTAssertNotNil(visible.lastAppliedLayoutPhysicalRect)
        XCTAssertNil(hidden.lastAppliedLayoutPhysicalRect)
        let floatingRect = try await floating.getAxRect()
        XCTAssertEqual(floatingRect, original)
        XCTAssertTrue(hidden.parent === root)
        XCTAssertTrue(floating.parent === workspace)
    }

    func testCommandPolicyKeepsSpaceLevelCommandsOutsideTheFence() throws {
        for text in ["focus left", "move right", "resize width +20", "layout floating", "join-with left",
                     "scrolling-center", "scrolling-width next", "flatten-workspace-tree"] {
            let command = try XCTUnwrap(parseCommand(text).unwrap().0)
            XCTAssertTrue(NativeTilingCoordinator.supports(command), text)
        }
        // Past a display edge the move runs after the fenced command; focus across displays
        // runs outside the fence as navigation.
        XCTAssertTrue(NativeTilingCoordinator.supports(try XCTUnwrap(parseCommand("move --boundaries all-monitors-outer-frame left").unwrap().0)))
        XCTAssertTrue(NativeCommandPolicy.isNativeNavigation(try XCTUnwrap(parseCommand("focus --boundaries all-monitors-outer-frame left").unwrap().0)))
        for text in ["workspace 2", "move-node-to-workspace 2",
                     "focus --boundaries all-monitors-outer-frame left"] {
            let command = try XCTUnwrap(parseCommand(text).unwrap().0)
            XCTAssertFalse(NativeTilingCoordinator.supports(command), text)
        }
    }

    func testRestoreDoesNotBorrowWindowFromAnotherSpaceOrFlattenIncompleteTree() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let group = TilingContainer(parent: root, adaptiveWeight: 1, .v, index: 0)
        let a = TestWindow.new(id: 1, parent: group)
        let b = TestWindow.new(id: 2, parent: group)
        for window in [a, b] {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
        }
        let record = NativePersistedLayout(workspace)
        let otherSpace = Workspace.get(byName: "other-space")
        b.bind(to: otherSpace.rootTilingContainer, adaptiveWeight: 1, index: 0)
        let store = NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertFalse(store.restore(record, to: workspace))
        XCTAssertTrue(workspace.rootTilingContainer === root)
        XCTAssertTrue(root.children.first === group)
        XCTAssertTrue(b.nodeWorkspace === otherSpace)
        b.bind(to: group, adaptiveWeight: 1, index: 1)
        XCTAssertTrue(store.restore(record, to: workspace))
        let restored = workspace.rootTilingContainer
        XCTAssertFalse(restored === root)
        let restoredGroup = try XCTUnwrap(restored.children.first as? TilingContainer)
        XCTAssertEqual(restoredGroup.children, [a, b])
    }

    func testScrollingDesktopWithTabGroupIsRestoredAfterRestart() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .v, index: 0)
        let windows = [TestWindow.new(id: 1, parent: tabs), TestWindow.new(id: 2, parent: tabs), TestWindow.new(id: 3, parent: root)]
        for window in windows {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
        }
        windows[2].scrollingColumnWidth = 0.6
        let record = NativePersistedLayout(workspace)
        XCTAssertTrue(record.supported)
        XCTAssertTrue(NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            .restore(record, to: workspace))
        XCTAssertEqual(windows[2].scrollingColumnWidth, 0.6)
    }

    func testQuittingRightAfterAStripChangeStillSavesIt() async throws {
        let workspace = nativeWorkspace()
        let a = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let b = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        for window in [a, b] {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
            window.scrollingColumnWidth = 0.8
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("layout.json")
        let persistence = NativeLayoutPersistence(url: url)
        let previous = runtime.native.persistence
        runtime.native.persistence = persistence
        defer { runtime.native.persistence = previous; TrayMenuModel.shared.isEnabled = true }
        await persistence.reconcile(runtime.native.layouts)
        await persistence.save(runtime.native.layouts)
        workspace.scrollingOffset = 280
        runtime.native.tiling.assumeReconciledForTests()
        runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
        // Let the layout run, then quit (or `enable off`) inside the 350 ms save debounce.
        try await Task.sleep(for: .milliseconds(100))
        await stopNativeTilingAndRestoreFrames()
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let spaces = try XCTUnwrap(records["spaces"] as? [String: [String: Any]])
        let desktop = try XCTUnwrap(spaces["desktop-a"])
        XCTAssertEqual(try XCTUnwrap(desktop["scrollingOffset"] as? Double), 280, accuracy: 1,
                       "A change made just before quitting must not be lost")
    }

    func testScrollingOnlyRelayoutPersistsViewportWithoutNativeRead() async throws {
        let workspace = nativeWorkspace()
        let a = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let b = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        for window in [a, b] {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
            window.scrollingColumnWidth = 0.8
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("layout.json")
        let persistence = NativeLayoutPersistence(url: url)
        let previous = runtime.native.persistence
        runtime.native.persistence = persistence
        defer { runtime.native.persistence = previous }
        await persistence.reconcile(runtime.native.layouts)
        await persistence.save(runtime.native.layouts)
        let original = try Data(contentsOf: url)
        workspace.scrollingOffset = 280
        runtime.native.tiling.assumeReconciledForTests()
        runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
        // A scrolling-only layout must eventually write the changed viewport.
        try await Task.sleep(for: .milliseconds(900))
        let updated = try Data(contentsOf: url)
        XCTAssertNotEqual(updated, original)
        let records = try XCTUnwrap(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        let spaces = try XCTUnwrap(records["spaces"] as? [String: [String: Any]])
        let desktop = try XCTUnwrap(spaces["desktop-a"])
        XCTAssertEqual(try XCTUnwrap(desktop["scrollingOffset"] as? Double), 280, accuracy: 1)
    }

    func testNativePersistenceRoundTripProtectsIncompleteSavedTreeFromAutosave() async throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let group = TilingContainer(parent: root, adaptiveWeight: 1, .v, index: 0)
        let a = TestWindow.new(id: 1, parent: group)
        let b = TestWindow.new(id: 2, parent: group)
        for window in [a, b] {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("native.json")
        let layouts = runtime.native.layouts
        let first = NativeLayoutPersistence(url: url)
        await first.reconcile(layouts)
        await first.save(layouts)
        XCTAssertNil(first.lastError)
        let original = try Data(contentsOf: url)
        let elsewhere = Workspace.get(byName: "elsewhere")
        b.bind(to: elsewhere.rootTilingContainer, adaptiveWeight: 1, index: 0)
        let second = NativeLayoutPersistence(url: url)
        await second.reconcile(layouts)
        XCTAssertEqual(second.pendingCount, 1)
        await second.save(layouts)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(b.nodeWorkspace === elsewhere)
        b.bind(to: group, adaptiveWeight: 1, index: 1)
        await second.reconcile(layouts)
        XCTAssertEqual(second.pendingCount, 0)
        let restoredGroup = try XCTUnwrap(workspace.rootTilingContainer.children.first as? TilingContainer)
        XCTAssertEqual(restoredGroup.children, [a, b])
    }

    func testExpiredRestoreWithNoMatchingWindowNeverErasesSavedStrip() async throws {
        let workspace = nativeWorkspace()
        let savedWindow = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        savedWindow.restartIdentity = RestartWindowIdentity(bundleId: "remembered.app", pid: 10,
            launchDate: Date(timeIntervalSince1970: 1), title: "document")
        savedWindow.scrollingColumnFixedWidth = 725
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("native.json")
        let first = NativeLayoutPersistence(url: url)
        await first.reconcile(runtime.native.layouts)
        await first.save(runtime.native.layouts)
        let original = try Data(contentsOf: url)

        savedWindow.unbindFromParent()
        let unrelated = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        unrelated.restartIdentity = RestartWindowIdentity(bundleId: "other.app", pid: 11,
            launchDate: Date(timeIntervalSince1970: 2), title: "other")
        let restored = NativeLayoutPersistence(url: url)
        let start = ContinuousClock.now
        restored.now = { start }
        await restored.reconcile(runtime.native.layouts)
        XCTAssertEqual(restored.pendingCount, 1)
        restored.now = { start.advanced(by: .seconds(120)) }
        await restored.reconcile(runtime.native.layouts)
        XCTAssertEqual(restored.pendingCount, 1, "No match must not release saved layout for overwrite")
        await restored.save(runtime.native.layouts)
        XCTAssertEqual(try Data(contentsOf: url), original)

        savedWindow.bind(to: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        await restored.reconcile(runtime.native.layouts)
        XCTAssertEqual(restored.pendingCount, 0)
        XCTAssertEqual(savedWindow.scrollingColumnFixedWidth, 725)
    }

    func testTemporarilyMissingSpaceDoesNotPruneItsPersistedLayout() async throws {
        let workspace = nativeWorkspace()
        let savedWindow = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        savedWindow.restartIdentity = RestartWindowIdentity(bundleId: "remembered.app", pid: 10,
            launchDate: Date(timeIntervalSince1970: 1), title: "document")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("native.json")
        let persistence = NativeLayoutPersistence(url: url)
        await persistence.reconcile(runtime.native.layouts)
        await persistence.save(runtime.native.layouts)
        let original = try Data(contentsOf: url)

        // A topology read may temporarily omit the Space while a display is
        // disconnected. Its last known strip must not be deleted.
        let next = NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a",
            activeSpaceID: "2", spaces: [NativeSpace(id: "2", uuid: "desktop-b", type: 0)])],
            windows: [], readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(next, for: inventory.invalidate()))
        runtime.native.layouts.reconcile(inventory, displays: [mainMonitor])
        await persistence.save(runtime.native.layouts)
        let updated = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let spaces = try XCTUnwrap(updated?["spaces"] as? [String: Any])
        XCTAssertNotNil(spaces["desktop-a"], "An absent Space must retain its last saved strip")
        XCTAssertNotEqual(try Data(contentsOf: url), Data(), "The persistence file remains readable")
        XCTAssertFalse(original.isEmpty)
    }

    func testUniqueFloatingWindowRestoresEvenIfAppInitiallyOpensItAsTiled() throws {
        let workspace = nativeWorkspace()
        let original = TestWindow.new(id: 1, parent: workspace)
        original.restartIdentity = RestartWindowIdentity(bundleId: "floating.app", pid: 21,
            launchDate: Date(timeIntervalSince1970: 1), title: "original")
        let record = NativePersistedLayout(workspace)
        original.unbindFromParent()

        let reopened = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        reopened.restartIdentity = RestartWindowIdentity(bundleId: "floating.app", pid: 22,
            launchDate: Date(timeIntervalSince1970: 2), title: "changed title")
        let store = NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertTrue(store.restore(record, to: workspace))
        XCTAssertTrue(reopened.parent === workspace, "An unambiguous saved floating window stays floating")
        XCTAssertFalse(workspace.rootTilingContainer.allLeafWindowsRecursive.contains(reopened))
    }

    func testAfterARebootWindowsOfOneAppArePairedInOrder() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .v, index: 0)
        let windows = [TestWindow.new(id: 1, parent: tabs), TestWindow.new(id: 2, parent: tabs), TestWindow.new(id: 3, parent: root)]
        for window in windows {
            window.restartIdentity = RestartWindowIdentity(bundleId: "terminal", pid: 99, launchDate: Date(timeIntervalSince1970: 1), title: "~")
        }
        let record = NativePersistedLayout(workspace)
        // Reboot: same app, new process, titles that repeat or changed, a flat new tree.
        let fresh = [TestWindow.new(id: 11, parent: root), TestWindow.new(id: 12, parent: root), TestWindow.new(id: 13, parent: root)]
        for window in windows { window.unbindFromParent() }
        for (i, window) in fresh.enumerated() {
            window.restartIdentity = RestartWindowIdentity(bundleId: "terminal", pid: 500, launchDate: Date(timeIntervalSince1970: 2), title: i == 0 ? "~" : "vim")
        }
        let store = NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertTrue(store.restore(record, to: workspace))
        let group = try XCTUnwrap(workspace.rootTilingContainer.children.first as? TilingContainer)
        XCTAssertEqual(group.children.map { ($0 as? Window)?.windowId }, [11, 12], "The tab group comes back, in creation order")
    }

    func testAMissingWindowIsDroppedFromTheRestoredTreeOnlyWhenPartialIsAllowed() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let split = TilingContainer(parent: root, adaptiveWeight: 1, .v, index: 0)
        let a = TestWindow.new(id: 1, parent: split)
        let b = TestWindow.new(id: 2, parent: split)
        let c = TestWindow.new(id: 3, parent: root)
        a.restartIdentity = RestartWindowIdentity(bundleId: "editor", pid: 99, launchDate: Date(timeIntervalSince1970: 1), title: "a")
        b.restartIdentity = RestartWindowIdentity(bundleId: "browser", pid: 98, launchDate: Date(timeIntervalSince1970: 1), title: "b")
        c.restartIdentity = RestartWindowIdentity(bundleId: "chat", pid: 97, launchDate: Date(timeIntervalSince1970: 1), title: "c")
        let record = NativePersistedLayout(workspace)
        b.unbindFromParent() // The browser never comes back.
        let store = NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertFalse(store.restore(record, to: workspace), "During the grace period the tree waits for every window")
        XCTAssertTrue(store.restore(record, to: workspace, allowPartial: true))
        XCTAssertEqual(Set(workspace.allLeafWindowsRecursive.map(\.windowId)), [1, 3])
    }

    func testAPinnedColumnIsRestoredWithItsDesktop() throws {
        let workspace = nativeWorkspace()
        let root = workspace.rootTilingContainer
        let windows = (1...3).map { TestWindow.new(id: UInt32($0), parent: root) }
        for window in windows {
            window.restartIdentity = RestartWindowIdentity(bundleId: "fixture", pid: 99,
                launchDate: Date(timeIntervalSince1970: 1), title: "\(window.windowId)")
        }
        workspace.scrollingPinnedNode = windows[2]
        workspace.scrollingPinSide = .right
        let record = NativePersistedLayout(workspace)
        let reloaded = try JSONDecoder().decode(NativePersistedLayout.self, from: JSONEncoder().encode(record))
        workspace.scrollingPinnedNode = nil
        XCTAssertTrue(NativeLayoutPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            .restore(reloaded, to: workspace))
        XCTAssertTrue(workspace.pinnedScrollingColumn === windows[2])
        XCTAssertEqual(workspace.scrollingPinSide, .right)
        // Files written before pins existed still load.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        json.removeValue(forKey: "pinnedWindowID"); json.removeValue(forKey: "pinSide")
        let old = try JSONDecoder().decode(NativePersistedLayout.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.pinnedWindowID)
    }

    func testUnreadableNativePersistenceIsNeverOverwritten() async throws {
        _ = nativeWorkspace()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("native.json")
        let original = Data("{invalid".utf8)
        try original.write(to: url)
        let store = NativeLayoutPersistence(url: url)
        await store.reconcile(runtime.native.layouts)
        await store.save(runtime.native.layouts)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testNativeCommandsRetainNestedGroupsAndRejectHiddenWindowTarget() async throws {
        let workspace = nativeWorkspace()
        let group = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .v, index: 0)
        let a = TestWindow.new(id: 1, parent: group)
        let b = TestWindow.new(id: 2, parent: group)
        _ = a.focusWindow()
        let result = try await NativeTilingCommandScope.$active.withValue(true) {
            try await parseCommand("balance-sizes").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(workspace.rootTilingContainer.children.first === group)
        XCTAssertEqual(group.children, [a, b])
        b.nativeLayoutEligible = false
        let rejected = try await NativeTilingCommandScope.$active.withValue(true) {
            try await parseCommand("resize --window-id 2 width +20").cmdOrDie.run(.defaultEnv, .emptyStdin)
        }
        XCTAssertNotEqual(rejected.exitCode, 0)
        XCTAssertTrue(rejected.stderr.joined().contains("eligible"))
        XCTAssertEqual(group.children, [a, b])
    }
}

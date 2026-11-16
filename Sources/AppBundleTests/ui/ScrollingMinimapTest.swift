@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ScrollingMinimapTest: WorkspaceTestCase {
    override func setUp() async throws {
        try await super.setUp()
        // Button clicks are sent through NSApp; a filtered run may start before anything creates it.
        _ = NSApplication.shared
    }

    private func fixture(count: Int = 3) -> (Workspace, [TestWindow]) {
        let workspace = focus.workspace
        let windows = (0..<count).map { TestWindow.new(id: UInt32(95500 + $0), parent: workspace.rootTilingContainer) }
        return (workspace, windows)
    }

    func testMapPreservesWidthRatiosAndTracksClampedViewport() throws {
        let (workspace, windows) = fixture()
        windows[0].scrollingColumnWidth = 0.25
        windows[1].scrollingColumnWidth = 0.5
        windows[2].scrollingColumnWidth = 0.75
        let metrics = workspace.scrollingMetrics
        let bounds = CGRect(x: 16, y: 32, width: 608, height: 58)
        let first = ScrollingMinimapGeometry(metrics: metrics, offset: metrics.offsetRange.lowerBound, bounds: bounds)
        let last = ScrollingMinimapGeometry(metrics: metrics, offset: metrics.offsetRange.upperBound, bounds: bounds)
        XCTAssertEqual(first.tiles[1].width / first.tiles[0].width, metrics.columns[1].width / metrics.columns[0].width, accuracy: 0.001)
        XCTAssertEqual(first.tiles[2].width / first.tiles[0].width, metrics.columns[2].width / metrics.columns[0].width, accuracy: 0.001)
        XCTAssertEqual(first.viewport.width / first.tiles[0].width, metrics.areaWidth / metrics.columns[0].width, accuracy: 0.001)
        for tile in first.tiles { XCTAssertEqual(tile.height, bounds.height, "Tiles fill the row") }
        XCTAssertLessThanOrEqual(first.tiles[0].minX, first.viewport.midX)
        XCTAssertEqual(last.tiles[2].maxX, last.viewport.maxX, accuracy: 1)
        XCTAssertGreaterThan(last.viewport.minX, first.viewport.minX)
        XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(first.viewport))
        XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(last.viewport))
    }

    func testOneNarrowColumnDoesNotStretchTheOthers() {
        // A 565 pt column beside two wider ones: it used to force every tile 1.27 times wider so
        // that it reached 32 pt, which made a full-width window look like a wide screen.
        let (workspace, windows) = fixture(count: 3)
        for (window, share) in zip(windows, [0.5, 1.0, 0.33]) { window.scrollingColumnWidth = share }
        let metrics = workspace.scrollingMetrics
        let height = scrollingMinimapRowHeight(metrics: metrics)
        let map = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: scrollingMinimapContentWidth(metrics: metrics, visibleWidth: 608), height: height))
        let areaHeight = metrics.geometry.area.height
        for (tile, column) in zip(map.tiles, metrics.columns) {
            XCTAssertEqual(tile.width / tile.height, column.width / areaHeight, accuracy: 0.001)
        }
        XCTAssertEqual(map.viewport.width / map.viewport.height, metrics.areaWidth / areaHeight, accuracy: 0.001,
                       "The viewport has the display's proportions")
    }

    func testSingleWindowIsCentredAndKeepsTheDisplaysShape() throws {
        let (workspace, _) = fixture(count: 1)
        let metrics = workspace.scrollingMetrics
        let map = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: 648, height: 72))
        let tile = try XCTUnwrap(map.tiles.first)
        XCTAssertEqual(tile.width / tile.height, metrics.areaWidth / metrics.geometry.area.height, accuracy: 0.001,
                       "A window filling the display is drawn with the display's proportions")
        XCTAssertLessThan(tile.width, 648 / 2, "Not stretched across the panel")
        XCTAssertEqual(tile.midX, 324, accuracy: 0.01)
        XCTAssertEqual(map.viewport, tile)
    }

    func testDenseTilesAndGapsRemainSelectable() throws {
        let (workspace, _) = fixture(count: 40)
        let metrics = workspace.scrollingMetrics
        // Forty columns at true scale are wider than the panel, so the canvas scrolls.
        let canvas = scrollingMinimapContentWidth(metrics: metrics, visibleWidth: 608)
        XCTAssertGreaterThan(canvas, 608)
        let height = scrollingMinimapRowHeight(metrics: metrics)
        let map = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: canvas, height: height))
        for (index, frame) in map.tiles.enumerated() {
            XCTAssertEqual(map.column(at: CGPoint(x: frame.midX, y: frame.midY)), index)
        }
        for x in stride(from: CGFloat(0), to: canvas, by: 2) {
            XCTAssertNotNil(map.column(at: CGPoint(x: x, y: height / 2)))
        }
        XCTAssertNil(map.column(at: CGPoint(x: -1, y: height / 2)))
    }

    func testExtremelyNarrowColumnCapsPanelHeightWhileKeepingTilesClickable() {
        let (workspace, windows) = fixture(count: 8)
        for (index, window) in windows.enumerated() {
            window.scrollingColumnWidth = index == 0 ? 0.1 : 0.5
        }
        let metrics = workspace.scrollingMetrics
        let rowHeight = scrollingMinimapRowHeight(metrics: metrics)
        XCTAssertEqual(rowHeight, 64, "A narrow column never changes the panel's height")
        let contentWidth = scrollingMinimapContentWidth(metrics: metrics, visibleWidth: 608)
        let geometry = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: contentWidth, height: rowHeight))
        XCTAssertGreaterThanOrEqual(geometry.tiles[0].width, scrollingMinimapMinimumTileWidth - 0.01)
        XCTAssertEqual(geometry.tiles.count, 8)
        XCTAssertEqual(geometry.viewport.height, 64)
        for (index, tile) in geometry.tiles.enumerated() {
            XCTAssertEqual(geometry.column(at: CGPoint(x: tile.midX, y: tile.midY)), index)
        }
    }

    func testPanelHugsACompactStripButKeepsRoomForItsHeader() {
        let (workspace, windows) = fixture(count: 4)
        windows.forEach { $0.scrollingColumnWidth = 0.5 }
        let metrics = workspace.scrollingMetrics
        let width = scrollingMinimapPanelWidth(metrics: metrics, maximum: 680)
        XCTAssertEqual(width, 320, "Four tiles at true scale need less than the header's minimum")
        let geometry = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: width - 32, height: scrollingMinimapRowHeight(metrics: metrics)))
        XCTAssertGreaterThanOrEqual(geometry.tiles.first?.minX ?? -1, -0.5, "The strip fits its hugging panel")
        XCTAssertLessThanOrEqual(geometry.tiles.last?.maxX ?? 1e9, width - 32 + 0.5)
        _ = (0..<20).map { TestWindow.new(id: UInt32(95600 + $0), parent: workspace.rootTilingContainer) }
        XCTAssertEqual(scrollingMinimapPanelWidth(metrics: workspace.scrollingMetrics, maximum: 680), 680, "Capped; the map scrolls")
    }

    func testTilesKeepTheirWindowsProportionsAndTheViewportTheDisplays() {
        let (workspace, windows) = fixture(count: 4)
        for (window, share) in zip(windows, [0.5, 1.0, 0.5, 0.75]) { window.scrollingColumnWidth = share }
        let metrics = workspace.scrollingMetrics
        let height = scrollingMinimapRowHeight(metrics: metrics)
        let width = scrollingMinimapContentWidth(metrics: metrics, visibleWidth: 608)
        XCTAssertEqual(width, 608, accuracy: 0.01, "The strip fits without scrolling")
        let geometry = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: width, height: height))
        let areaHeight = metrics.geometry.area.height
        for (tile, column) in zip(geometry.tiles, metrics.columns) {
            XCTAssertEqual(tile.width / tile.height, column.width / areaHeight, accuracy: 0.001,
                           "A window is drawn in its own proportions, so a full-width one is not a wide screen")
            XCTAssertGreaterThanOrEqual(tile.width, scrollingMinimapMinimumTileWidth - 0.01)
        }
        XCTAssertEqual(geometry.viewport.width / geometry.viewport.height, metrics.areaWidth / areaHeight, accuracy: 0.001,
                       "The visible part has the display's proportions")
        // Twice as wide a column is twice as wide a tile.
        XCTAssertEqual(geometry.tiles[1].width / geometry.tiles[0].width, metrics.columns[1].width / metrics.columns[0].width,
                       accuracy: 0.001)
        let left = geometry.tiles.first?.minX ?? 0, right = 608 - (geometry.tiles.last?.maxX ?? 0)
        XCTAssertEqual(left, right, accuracy: 1, "Centred")
    }

    func testUnequalDenseMinimapTilesStayAtLeastThirtyTwoPointsAndDoNotOverlap() {
        let (workspace, windows) = fixture(count: 40)
        for (index, window) in windows.enumerated() {
            window.scrollingColumnWidth = index == 0 ? 0.1 : index == 1 ? 0.2 : 1
        }
        let metrics = workspace.scrollingMetrics
        let contentWidth = scrollingMinimapContentWidth(metrics: metrics, visibleWidth: 608)
        let map = ScrollingMinimapGeometry(metrics: metrics, offset: 0,
            bounds: CGRect(x: 0, y: 0, width: contentWidth, height: scrollingMinimapRowHeight(metrics: metrics)))
        XCTAssertGreaterThan(contentWidth, 608)
        for tile in map.tiles { XCTAssertGreaterThanOrEqual(tile.width, scrollingMinimapMinimumTileWidth - 0.01) }
        for pair in zip(map.tiles, map.tiles.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX + 0.01)
        }
    }

    func testScrollCanvasKeepsTilesAlignedAndFollowsTheVisibleEndOfTheWorkspace() throws {
        let (workspace, windows) = fixture(count: 40)
        let metrics = workspace.scrollingMetrics
        let models = windows.map { ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1) }
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 640, height: 120))
        view.update(workspaceName: workspace.name, models: models, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.upperBound, focused: ObjectIdentifier(windows[39]))
        let scroll = try XCTUnwrap(minimapDescendants(of: view).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertTrue(document.isFlipped, "The scroll canvas must use the map's top-left coordinates")
        let buttons = document.subviews.compactMap { $0 as? NSButton }
        let first = try XCTUnwrap(buttons.first)
        let last = try XCTUnwrap(buttons.last)
        XCTAssertEqual(view.convert(first.bounds, from: first).minY, 29, accuracy: 0.5)
        XCTAssertEqual(first.bounds.height, scrollingMinimapRowHeight(metrics: metrics), "Tiles fill the row")
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)
        XCTAssertTrue(scroll.documentVisibleRect.intersects(last.frame), "The map must follow the viewport at the strip end")
        view.resetPresentation()
        view.update(workspaceName: workspace.name, models: models, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.lowerBound, focused: ObjectIdentifier(windows[0]))
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.01)
    }

    func testDragEdgeScrollStaysWithinCanvasAndKeepsDragDeltaFinite() {
        XCTAssertEqual(scrollingMinimapEdgeScrollDelta(pointerX: 8, viewportWidth: 400,
            contentOffset: 100, contentWidth: 1600), -13.5, accuracy: 0.001)
        XCTAssertEqual(scrollingMinimapEdgeScrollDelta(pointerX: 392, viewportWidth: 400,
            contentOffset: 100, contentWidth: 1600), 13.5, accuracy: 0.001)
        XCTAssertEqual(scrollingMinimapEdgeScrollDelta(pointerX: 200, viewportWidth: 400,
            contentOffset: 100, contentWidth: 1600), 0)
        XCTAssertEqual(scrollingMinimapEdgeScrollDelta(pointerX: 0, viewportWidth: 400,
            contentOffset: 0, contentWidth: 1600), 0)
        XCTAssertEqual(scrollingMinimapEdgeScrollDelta(pointerX: 400, viewportWidth: 400,
            contentOffset: 1200, contentWidth: 1600), 0)
        XCTAssertEqual(scrollingMinimapEdgeScrollDelta(pointerX: 400, viewportWidth: 400,
            contentOffset: 0, contentWidth: 400), 0)
        XCTAssertEqual(scrollingMinimapEdgeScrollDelta(pointerX: .nan, viewportWidth: 400,
            contentOffset: 100, contentWidth: 1600), 0)
    }

    func testMinimapDragInsertionSlotsMatchReorderOnBothEdges() {
        let centers: [CGFloat] = [40, 100, 160, 220]
        XCTAssertEqual(scrollingMinimapInsertionIndex(-10, otherMidpoints: centers), 0)
        XCTAssertEqual(scrollingMinimapInsertionIndex(40, otherMidpoints: centers), 0)
        XCTAssertEqual(scrollingMinimapInsertionIndex(75, otherMidpoints: centers), 1)
        XCTAssertEqual(scrollingMinimapInsertionIndex(130, otherMidpoints: centers), 2)
        XCTAssertEqual(scrollingMinimapInsertionIndex(300, otherMidpoints: centers), 4)
    }

    func testMinimapStressWithOneHundredTwentyUnequalColumnsAndViewportExtremes() throws {
        let (workspace, windows) = fixture(count: 120)
        for (index, window) in windows.enumerated() {
            window.scrollingColumnWidth = [0.1, 0.25, 0.5, 1.0][index % 4]
        }
        let metrics = workspace.scrollingMetrics
        let height = scrollingMinimapRowHeight(metrics: metrics)
        let contentWidth = scrollingMinimapContentWidth(metrics: metrics, visibleWidth: 560)
        XCTAssertTrue(height.isFinite && contentWidth.isFinite)
        XCTAssertGreaterThan(contentWidth, 560)
        for offset in [metrics.offsetRange.lowerBound,
                       (metrics.offsetRange.lowerBound + metrics.offsetRange.upperBound) / 2,
                       metrics.offsetRange.upperBound] {
            let map = ScrollingMinimapGeometry(metrics: metrics, offset: offset,
                bounds: CGRect(x: 0, y: 0, width: contentWidth, height: height))
            XCTAssertEqual(map.tiles.count, 120)
            XCTAssertTrue(map.viewport.minX.isFinite && map.viewport.maxX.isFinite)
            for (index, tile) in map.tiles.enumerated() {
                XCTAssertTrue(tile.minX.isFinite && tile.width.isFinite && tile.height.isFinite)
                XCTAssertGreaterThanOrEqual(tile.width, scrollingMinimapMinimumTileWidth - 0.01)
                XCTAssertEqual(map.column(at: CGPoint(x: tile.midX, y: tile.midY)), index)
            }
            for pair in zip(map.tiles, map.tiles.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX + 0.01)
            }
        }
    }

    func testMinimapRepeatedEdgeDraggingCannotEscapeDocument() {
        let viewport: CGFloat = 560
        let content: CGFloat = 4800
        var offset: CGFloat = 0
        for _ in 0..<2000 {
            let delta = scrollingMinimapEdgeScrollDelta(pointerX: 559, viewportWidth: viewport,
                contentOffset: offset, contentWidth: content)
            XCTAssertTrue(delta.isFinite)
            XCTAssertGreaterThanOrEqual(delta, 0)
            offset += delta
            XCTAssertLessThanOrEqual(offset, content - viewport + 0.001)
        }
        XCTAssertEqual(offset, content - viewport, accuracy: 0.001)
        for _ in 0..<2000 {
            let delta = scrollingMinimapEdgeScrollDelta(pointerX: 1, viewportWidth: viewport,
                contentOffset: offset, contentWidth: content)
            XCTAssertTrue(delta.isFinite)
            XCTAssertLessThanOrEqual(delta, 0)
            offset += delta
            XCTAssertGreaterThanOrEqual(offset, -0.001)
        }
        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func testMinimapInsertionIndexWithManyColumnsAndReorderedIdentities() {
        let centers = (0..<120).map { CGFloat($0) * 35 + 17.5 }
        for index in centers.indices {
            XCTAssertEqual(scrollingMinimapInsertionIndex(centers[index] + 1,
                otherMidpoints: centers), index + 1)
        }
        XCTAssertEqual(scrollingMinimapInsertionIndex(-1000, otherMidpoints: centers), 0)
        XCTAssertEqual(scrollingMinimapInsertionIndex(100000, otherMidpoints: centers), centers.count)
        XCTAssertEqual(scrollingMinimapInsertionIndex(0, otherMidpoints: []), 0)
    }

    func testMinimapCanRepeatedlyRefreshLargeModelWithoutRecreatingTiles() throws {
        let (workspace, windows) = fixture(count: 100)
        let metrics = workspace.scrollingMetrics
        let models = windows.map {
            ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1)
        }
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 640, height: 120))
        view.update(workspaceName: "Stress", models: models, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.lowerBound, focused: models[0].id)
        let scroll = try XCTUnwrap(minimapDescendants(of: view).compactMap { $0 as? NSScrollView }.first)
        let initial = try XCTUnwrap(scroll.documentView?.subviews.compactMap { $0 as? ScrollingMinimapButton })
        XCTAssertEqual(initial.count, 100)
        for index in 0..<50 {
            let offset = index.isMultiple(of: 2) ? metrics.offsetRange.upperBound : metrics.offsetRange.lowerBound
            view.update(workspaceName: "Stress", models: models, icons: [:], metrics: metrics,
                        offset: offset, focused: models[index].id)
            let current = try XCTUnwrap(scroll.documentView?.subviews.compactMap { $0 as? ScrollingMinimapButton })
            XCTAssertEqual(current.count, initial.count)
            XCTAssertTrue(zip(current, initial).allSatisfy { pair in pair.0 === pair.1 },
                          "Viewport and focus updates must reuse existing buttons")
        }
        view.resetPresentation()
    }

    func testPinnedColumnGetsItsOwnTileBesideTheStrip() throws {
        let (workspace, windows) = fixture(count: 4)
        let metrics = workspace.scrollingMetrics
        let models = windows.dropFirst().map { ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1) }
        var pinned = ScrollingMinimapTile(id: ObjectIdentifier(windows[0]), title: "Chat", applications: [], count: 1)
        pinned.pinned = .left
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 640, height: 120))
        var selected: ObjectIdentifier?
        view.selected = { selected = $0 }
        view.update(workspaceName: workspace.name, models: models, pinned: pinned, icons: [:], metrics: metrics,
                    offset: 0, focused: nil)
        let scroll = try XCTUnwrap(minimapDescendants(of: view).compactMap { $0 as? NSScrollView }.first)
        let pinButton = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(scroll.documentView?.subviews.compactMap { $0 as? NSButton }.count, 3, "The strip keeps only its columns")
        XCTAssertLessThan(pinButton.frame.maxX, scroll.frame.minX, "Pinned left sits left of the strip")
        XCTAssertTrue(pinButton.accessibilityLabel()?.contains("pinned left") == true)
        pinButton.performClick(nil)
        XCTAssertEqual(selected, ObjectIdentifier(windows[0]))
        view.update(workspaceName: workspace.name, models: models, icons: [:], metrics: metrics, offset: 0, focused: nil)
        XCTAssertTrue(view.subviews.compactMap { $0 as? NSButton }.isEmpty, "Unpinning removes the tile")
    }

    func testPausedPanAndHoverDoNotExpireAndExitGetsFullGracePeriod() throws {
        var lifetime = ScrollingMinimapLifetime()
        lifetime.activity(at: 0)
        XCTAssertEqual(lifetime.dismissalDelay(at: 0.5), 1)
        lifetime.pan(true, at: 0.6)
        XCTAssertNil(lifetime.dismissalDelay(at: 100))
        lifetime.pan(false, at: 100)
        XCTAssertEqual(lifetime.dismissalDelay(at: 100), 1.5)
        lifetime.hover(true, at: 101.4)
        XCTAssertNil(lifetime.dismissalDelay(at: 200))
        lifetime.hover(false, at: 200)
        XCTAssertEqual(lifetime.dismissalDelay(at: 201), 0.5)
        lifetime.activity(at: 201)
        XCTAssertEqual(lifetime.dismissalDelay(at: 201.5), 1)
        XCTAssertEqual(lifetime.dismissalDelay(at: 203), 0)
    }

    func testClickUsesGroupIdentityAfterReorderAndRevealsWithoutRebuilding() async throws {
        let (workspace, windows) = fixture()
        let root = workspace.rootTilingContainer
        let selected = windows[2]
        let id = ObjectIdentifier(selected)
        selected.unbindFromParent()
        selected.bind(to: root, adaptiveWeight: 1, index: 0)
        let groups = root.children
        let metrics = workspace.scrollingMetrics
        let column = try XCTUnwrap(metrics.columns.first(where: { $0.node === selected }))
        let expected = metrics.revealedOffset(for: column, current: workspace.scrollingOffset)
        XCTAssertTrue(focusScrollingMinimapGroup(id, in: workspace))
        try await workspace.layoutWorkspace()
        XCTAssertTrue(focus.windowOrNil === selected)
        XCTAssertEqual(workspace.scrollingOffset, expected, accuracy: 1)
        XCTAssertEqual(root.children, groups)
        selected.unbindFromParent()
        XCTAssertFalse(focusScrollingMinimapGroup(id, in: workspace))
    }

    func testCommandValidationAndDefaultShortcut() async throws {
        let (workspace, _) = fixture()
        let command = try XCTUnwrap(parseCommand("scrolling-minimap").cmdOrNil)
        _ = workspace
        let shown = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(shown.exitCode, 0)
        config.scrolling.minimapEnabled = false
        let disabled = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertNotEqual(disabled.exitCode, 0)
        XCTAssertTrue(defaultConfig.modes[mainModeId]?.bindings["alt-ctrl-m"]?.commands.first is ScrollingMinimapCommand)
    }

    func testExplicitOpenHoldsAndKeyboardSelectionSurvivesModelRefresh() throws {
        var lifetime = ScrollingMinimapLifetime()
        lifetime.openExplicitly(at: 1)
        XCTAssertTrue(lifetime.isExplicitlyOpen)
        XCTAssertNil(lifetime.dismissalDelay(at: 500))
        lifetime.closeExplicitly()
        XCTAssertEqual(lifetime.dismissalDelay(at: 500), 0)
        let (workspace, windows) = fixture()
        let models = windows.map { ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1) }
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 600, height: 120))
        var selected: ObjectIdentifier?
        var dismissed = false
        view.selected = { selected = $0 }
        view.dismissRequested = { dismissed = true }
        func update() {
            view.update(workspaceName: workspace.name, models: models, icons: [:], metrics: workspace.scrollingMetrics,
                        offset: workspace.scrollingOffset, focused: ObjectIdentifier(windows[0]))
        }
        func key(_ code: UInt16) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        }
        update()
        view.beginKeyboardNavigation()
        view.keyDown(with: try key(124))
        update()
        view.keyDown(with: try key(36))
        XCTAssertEqual(selected, ObjectIdentifier(windows[1]))
        view.keyDown(with: try key(53))
        XCTAssertTrue(dismissed)
    }

    func testFloatingWindowsGetChipsThatFocusThem() throws {
        let (workspace, windows) = fixture(count: 3)
        let metrics = workspace.scrollingMetrics
        let models = windows.map { ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1) }
        let height = scrollingMinimapRowHeight(metrics: metrics) + 80 + scrollingMinimapFloatingRowHeight
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 640, height: height))
        var picked: UInt32?
        view.floatingSelected = { picked = $0 }
        let floating = [ScrollingMinimapFloatingWindow(windowId: 501, pid: 1, title: "Calculator"),
                        ScrollingMinimapFloatingWindow(windowId: 502, pid: 2, title: "Settings", focused: true)]
        view.update(workspaceName: "Desktop", models: models, floating: floating, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.lowerBound, focused: nil)
        let chips = view.subviews.compactMap { $0 as? ScrollingMinimapFloatingChip }
        XCTAssertEqual(chips.map(\.model.title), ["Calculator", "Settings"])
        let scroll = try XCTUnwrap(minimapDescendants(of: view).compactMap { $0 as? NSScrollView }.first)
        XCTAssertGreaterThan(chips[0].frame.minY, scroll.frame.maxY, "Below the strip")
        XCTAssertLessThan(chips[0].frame.maxY, view.bounds.height - 23, "Above the footer")
        chips[1].performClick(nil)
        XCTAssertEqual(picked, 502)
        view.update(workspaceName: "Desktop", models: models, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.lowerBound, focused: nil)
        XCTAssertTrue(view.subviews.compactMap { $0 as? ScrollingMinimapFloatingChip }.isEmpty)
    }

    func testCompactMinimapHasHeaderPositionBarAndSelectedFooter() throws {
        let (workspace, windows) = fixture(count: 5)
        let metrics = workspace.scrollingMetrics
        let models = windows.map {
            ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1)
        }
        let height = scrollingMinimapRowHeight(metrics: metrics) + 80
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 640, height: height))
        view.update(workspaceName: "Desktop", models: models, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.lowerBound, focused: models[2].id)
        let scroll = try XCTUnwrap(minimapDescendants(of: view).compactMap { $0 as? NSScrollView }.first)
        XCTAssertLessThan(scroll.frame.maxY + 8, view.bounds.height - 23,
                          "Position track must fit between tiles and selected footer")
        XCTAssertEqual(scroll.documentView?.subviews.compactMap { $0 as? ScrollingMinimapButton }.count, 5)
        XCTAssertLessThanOrEqual(scroll.frame.maxY, view.bounds.height)
    }

    func testIconArrivalRefreshesExistingTileWithoutRebuildingIt() throws {
        let (workspace, windows) = fixture()
        let models = windows.map {
            ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [99], count: 1)
        }
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 640, height: 120))
        let metrics = workspace.scrollingMetrics
        view.update(workspaceName: "Desktop", models: models, icons: [:], metrics: metrics,
                    offset: 0, focused: models[0].id)
        let scroll = try XCTUnwrap(minimapDescendants(of: view).compactMap { $0 as? NSScrollView }.first)
        let tile = try XCTUnwrap(scroll.documentView?.subviews.compactMap { $0 as? ScrollingMinimapButton }.first)
        XCTAssertTrue(tile.icons.isEmpty)
        let image = try XCTUnwrap(NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil))
        view.update(workspaceName: "Desktop", models: models, icons: [99: image], metrics: metrics,
                    offset: 0, focused: models[0].id)
        let refreshed = try XCTUnwrap(scroll.documentView?.subviews.compactMap { $0 as? ScrollingMinimapButton }.first)
        XCTAssertTrue(tile === refreshed, "Updated icons should reuse the original button")
        // What the tile draws, not AppKit's needsDisplay flag, which a view outside a window does not keep.
        XCTAssertTrue(refreshed.icons.first === image, "A late-arriving icon must reach its tile")
    }

    func testRenderAccessibleTilesInLightAndDarkLayouts() throws {
        let (workspace, windows) = fixture()
        windows[0].scrollingColumnWidth = 0.25
        windows[1].scrollingColumnWidth = 0.5
        windows[2].scrollingColumnWidth = 0.75
        let titles = ["Design system", "StripMuxX · scrolling workspaces", "Research and references"]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StripMuxX-minimap-previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = MinimapPreviewHost(frame: CGRect(x: 0, y: 0, width: 640,
                height: scrollingMinimapRowHeight(metrics: workspace.scrollingMetrics) + 80))
            let view = ScrollingMinimapView(frame: host.bounds)
            host.addSubview(view)
            let window = NSWindow(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            window.setFrameOrigin(CGPoint(x: -20000, y: -20000))
            window.orderFront(nil)
            defer { window.close() }
            let models = windows.enumerated().map { index, window in
                ScrollingMinimapTile(id: ObjectIdentifier(window), title: titles[index], applications: [Int32(index)],
                    count: index + 1)
            }
            let icons = [0: "paintpalette.fill", 1: "terminal.fill", 2: "doc.text.fill"].compactMapValues {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }
            view.update(workspaceName: "Code", models: models, icons: Dictionary(uniqueKeysWithValues: icons.map { (Int32($0.key), $0.value) }),
                        metrics: workspace.scrollingMetrics, offset: 350, focused: ObjectIdentifier(windows[1]))
            let buttons = minimapDescendants(of: view).compactMap { $0 as? NSButton }
            XCTAssertEqual(buttons.count, 3)
            for (index, button) in buttons.enumerated() {
                XCTAssertGreaterThanOrEqual(button.frame.width, scrollingMinimapMinimumTileWidth - 0.01)
                XCTAssertTrue(button.superview?.bounds.contains(button.frame) == true)
                XCTAssertTrue(button.accessibilityLabel()?.contains(titles[index]) == true)
            }
            view.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let selectedTile = view.convert(buttons[1].bounds, from: buttons[1])
            let tileColor = bitmap.colorAt(x: Int(selectedTile.midX * scale), y: Int((selectedTile.minY + 5) * scale))
            let background = bitmap.colorAt(x: Int(5 * scale), y: Int(100 * scale))
            XCTAssertNotEqual(tileColor, background, "The preview must contain rendered tiles, not a blank host")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("\(appearance.rawValue).png"))
        }
    }

    func testContinuousCornersStayInsideTheRectAndActuallyRoundIt() {
        let rect = CGRect(x: 20, y: 10, width: 120, height: 60)
        let path = continuousRoundedRect(rect, radius: 10)
        XCTAssertEqual(path.bounds.minX, rect.minX, accuracy: 0.001)
        XCTAssertEqual(path.bounds.maxX, rect.maxX, accuracy: 0.001)
        XCTAssertEqual(path.bounds.minY, rect.minY, accuracy: 0.001)
        XCTAssertEqual(path.bounds.maxY, rect.maxY, accuracy: 0.001)
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            let inward = CGPoint(x: corner.x + (corner.x == rect.minX ? 1 : -1), y: corner.y + (corner.y == rect.minY ? 1 : -1))
            XCTAssertFalse(path.contains(inward), "The very corner of the rect is cut away")
            let deeper = CGPoint(x: corner.x + (corner.x == rect.minX ? 6 : -6), y: corner.y + (corner.y == rect.minY ? 6 : -6))
            XCTAssertTrue(path.contains(deeper), "and the shape is full a few points in")
        }
        for edge in [CGPoint(x: rect.midX, y: rect.minY + 0.5), CGPoint(x: rect.midX, y: rect.maxY - 0.5),
                     CGPoint(x: rect.minX + 0.5, y: rect.midY), CGPoint(x: rect.maxX - 0.5, y: rect.midY)] {
            XCTAssertTrue(path.contains(edge), "The straight edges reach the rect")
        }
        // A rect smaller than the radius gets a smaller radius instead of a tangled path.
        let small = continuousRoundedRect(CGRect(x: 0, y: 0, width: 14, height: 14), radius: 10)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 14, height: 14).contains(small.bounds))
        XCTAssertTrue(small.contains(CGPoint(x: 7, y: 7)))
    }

    func testCornerRadiiNestFromTileToViewportToPanel() {
        XCTAssertLessThan(scrollingMinimapTileRadius, scrollingMinimapViewportRadius)
        XCTAssertLessThan(scrollingMinimapViewportRadius, scrollingMinimapPanelRadius)
    }

    func testBlurMaskIsRoundedAndStretchesWithItsCornersIntact() throws {
        let mask = roundedBlurMask(radius: 18)
        XCTAssertEqual(mask.resizingMode, .stretch)
        XCTAssertEqual(mask.capInsets.top, 28, "The fixed corners hold a whole continuous corner")
        XCTAssertEqual(mask.size.width, 28 * 2 + 2)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(mask.tiffRepresentation)))
        func alpha(_ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? -1 }
        XCTAssertEqual(alpha(0, 0), 0, accuracy: 0.01, "The corner is cut away, so the blur there is not drawn")
        XCTAssertEqual(alpha(rep.pixelsWide / 2, rep.pixelsHigh / 2), 1, accuracy: 0.01)
        XCTAssertEqual(alpha(rep.pixelsWide / 2, 0), 1, accuracy: 0.01, "and the straight edges are full")
    }

    func testDesktopRowOffersEachDesktopOfTheDisplayAndSwitchesOnClick() throws {
        let workspace = focus.workspace
        let other = Workspace.get(byName: "b")
        let window = TestWindow.new(id: 96300, parent: workspace.rootTilingContainer)
        let metrics = workspace.scrollingMetrics
        let desktops = scrollingMinimapDesktops([(1, workspace), (2, other)], showing: workspace)
        XCTAssertEqual(desktops, [.init(number: 1, isCurrent: true, apps: .none), .init(number: 2, isCurrent: false, apps: .none)])
        XCTAssertEqual(scrollingMinimapDesktops([(1, workspace)], showing: workspace), [], "One desktop has nothing to switch to")

        let models = [ScrollingMinimapTile(id: ObjectIdentifier(window), title: "Window", applications: [], count: 1)]
        let rowHeight = scrollingMinimapRowHeight(metrics: metrics)
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 360, height: rowHeight + 68 + scrollingMinimapDesktopRowHeight))
        var selected: Int?
        view.desktopSelected = { selected = $0 }
        view.update(workspaceName: "Desktop 1", models: models, desktops: desktops, icons: [:], metrics: metrics,
                    offset: 0, focused: models[0].id)
        let chips = view.subviews.compactMap { $0 as? ScrollingMinimapDesktopChip }
        XCTAssertEqual(chips.map(\.model.number), [1, 2])
        XCTAssertEqual(chips.map(\.model.isCurrent), [true, false])
        XCTAssertTrue(chips.allSatisfy { !$0.isHidden })
        chips[1].performClick(nil)
        XCTAssertEqual(selected, 2, "Clicking a desktop asks to switch to it")
        XCTAssertGreaterThan(chips[0].frame.minY, 29 + rowHeight, "The row sits below the tiles")
        XCTAssertLessThanOrEqual(chips[0].frame.maxY, view.bounds.height - 23, "and above the footer")
        XCTAssertEqual(chips[0].accessibilityLabel(), "Desktop 1")
        XCTAssertEqual(chips[0].accessibilityValue() as? String, "Current")
        XCTAssertEqual(chips[1].accessibilityValue() as? String, "")
    }

    func testDesktopRowSitsAboveTheFloatingWindowsRowAndLeavesWhenThereIsNoChoice() throws {
        let workspace = focus.workspace
        let other = Workspace.get(byName: "b")
        let window = TestWindow.new(id: 96310, parent: workspace.rootTilingContainer)
        let metrics = workspace.scrollingMetrics
        let models = [ScrollingMinimapTile(id: ObjectIdentifier(window), title: "Window", applications: [], count: 1)]
        let floating = [ScrollingMinimapFloatingWindow(windowId: 1, pid: 1, title: "Calculator", focused: false)]
        let height = scrollingMinimapRowHeight(metrics: metrics) + 68 + scrollingMinimapFloatingRowHeight + scrollingMinimapDesktopRowHeight
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 360, height: height))
        let desktops = scrollingMinimapDesktops([(1, workspace), (2, other)], showing: workspace)
        view.update(workspaceName: "Desktop 1", models: models, floating: floating, desktops: desktops, icons: [:],
                    metrics: metrics, offset: 0, focused: models[0].id)
        let desktopChip = try XCTUnwrap(view.subviews.compactMap { $0 as? ScrollingMinimapDesktopChip }.first)
        let floatingChip = try XCTUnwrap(view.subviews.compactMap { $0 as? ScrollingMinimapFloatingChip }.first)
        XCTAssertLessThanOrEqual(desktopChip.frame.maxY, floatingChip.frame.minY, "Desktops above floating windows")

        view.update(workspaceName: "Desktop 1", models: models, floating: floating, desktops: [], icons: [:],
                    metrics: metrics, offset: 0, focused: models[0].id)
        XCTAssertTrue(view.subviews.compactMap { $0 as? ScrollingMinimapDesktopChip }.isEmpty, "No row for one desktop")
    }

    func testAnOpenMinimapFollowsItsDisplayToTheDesktopNowShowingThere() {
        let shown = focus.workspace
        let next = Workspace.get(byName: "b")
        XCTAssertTrue(scrollingMinimapDesktopToFollow(shown: shown, active: next) === next, "It moves to the new desktop")
        XCTAssertNil(scrollingMinimapDesktopToFollow(shown: shown, active: shown), "and stays put while nothing changed")
        XCTAssertNil(scrollingMinimapDesktopToFollow(shown: shown, active: nil), "or while the display shows no ordinary desktop")
    }

    private func display(_ index: Int, _ frame: CGRect, desktop: Int? = 1, shown: Bool = false, windows: Bool = true,
                         apps: ScrollingMinimapApps = .none) -> ScrollingMinimapDisplay {
        ScrollingMinimapDisplay(index: index, name: "D\(index)", frame: frame, desktop: desktop, isShown: shown, hasWindows: windows, apps: apps)
    }

    func testDisplaysAreDrawnWhereTheyReallyAreAndNeverLeaveTheirBox() {
        let area = CGSize(width: 240, height: 60)
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // Beside: a display to the right is drawn to the right, level with the first.
        let beside = scrollingMinimapDisplayFrames([display(0, main), display(1, CGRect(x: 1920, y: 0, width: 1920, height: 1080))], in: area)
        XCTAssertLessThan(beside[0].maxX, beside[1].minX)
        XCTAssertEqual(beside[0].minY, beside[1].minY, accuracy: 0.001)
        // Above: coordinates grow downward, so a display above has a negative y and is drawn above.
        let above = scrollingMinimapDisplayFrames([display(0, CGRect(x: 0, y: -1080, width: 1920, height: 1080)), display(1, main)], in: area)
        XCTAssertLessThan(above[0].maxY, above[1].minY)
        XCTAssertEqual(above[0].minX, above[1].minX, accuracy: 0.001)
        // One scale for all: same-size displays get same-size miniatures, whatever the arrangement.
        XCTAssertEqual(above[0].width, above[1].width, accuracy: 0.001)
        XCTAssertEqual(above[0].height, above[1].height, accuracy: 0.001)
        // An L of three displays stays inside the box and keeps every relation.
        let l = scrollingMinimapDisplayFrames([display(0, main), display(1, CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
                                               display(2, CGRect(x: 0, y: -1080, width: 1920, height: 1080))], in: area)
        for frame in beside + above + l { XCTAssertTrue(CGRect(origin: .zero, size: area).contains(frame), "\(frame) is outside \(area)") }
        XCTAssertLessThan(l[2].maxY, l[0].minY)
        XCTAssertLessThan(l[0].maxX, l[1].minX)
        XCTAssertTrue(scrollingMinimapDisplayFrames([], in: area).isEmpty)
    }

    func testTallArrangementsGetMoreRoomAndASingleDisplayGetsNone() {
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let side = [display(0, main), display(1, CGRect(x: 1920, y: 0, width: 1920, height: 1080))]
        let stacked = [display(0, CGRect(x: 0, y: -1080, width: 1920, height: 1080)), display(1, main)]
        XCTAssertEqual(scrollingMinimapDisplayRowHeight([display(0, main)]), 0, "Nothing to arrange")
        XCTAssertGreaterThan(scrollingMinimapDisplayRowHeight(stacked), scrollingMinimapDisplayRowHeight(side),
                             "A display above another needs height for its icons")
    }

    func testDisplayButtonsShowDesktopAndAppsAndOnlyAWindowedDisplayCanBeClicked() throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 96320, parent: workspace.rootTilingContainer)
        let metrics = workspace.scrollingMetrics
        let models = [ScrollingMinimapTile(id: ObjectIdentifier(window), title: "Window", applications: [], count: 1)]
        let top = CGRect(x: 0, y: -1080, width: 1920, height: 1080), bottom = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let apps = ScrollingMinimapApps(pids: [7, 8], names: ["Terminal", "Rex"])
        let displays = [display(0, top, desktop: 4, windows: true, apps: apps),
                        display(1, bottom, desktop: 1, shown: true, apps: .none),
                        display(2, CGRect(x: 1920, y: 0, width: 1920, height: 1080), desktop: 5, windows: false)]
        let rowHeight = scrollingMinimapDisplayRowHeight(displays)
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 360, height: scrollingMinimapRowHeight(metrics: metrics) + 68 + rowHeight))
        var clicked: Int?
        view.displaySelected = { clicked = $0 }
        view.update(workspaceName: "Desktop 1", models: models, displays: displays, icons: [:], metrics: metrics, offset: 0, focused: models[0].id)
        let buttons = view.subviews.compactMap { $0 as? ScrollingMinimapDisplayButton }
        XCTAssertEqual(buttons.map(\.model.index), [0, 1, 2])
        XCTAssertEqual(buttons.map(\.isEnabled), [true, false, false], "The shown display and an empty one cannot be clicked")
        XCTAssertEqual(buttons[0].toolTip, "D0 · Desktop 4 · Terminal, Rex", "The tooltip says which apps are there")
        XCTAssertEqual(buttons[2].accessibilityValue() as? String, "No windows")
        XCTAssertEqual(buttons[1].accessibilityValue() as? String, "Shown")
        XCTAssertLessThan(buttons[0].frame.maxY, buttons[1].frame.minY, "The display above is drawn above")
        buttons[0].performClick(nil)
        XCTAssertEqual(clicked, 0)
        buttons[2].performClick(nil)
        XCTAssertEqual(clicked, 0, "An empty display does nothing")
    }

    func testDesktopButtonsNameTheAppsOnEachDesktop() throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 96330, parent: workspace.rootTilingContainer)
        let metrics = workspace.scrollingMetrics
        let models = [ScrollingMinimapTile(id: ObjectIdentifier(window), title: "Window", applications: [], count: 1)]
        let desktops = [ScrollingMinimapDesktop(number: 1, isCurrent: true, apps: ScrollingMinimapApps(pids: [1], names: ["Safari"])),
                        ScrollingMinimapDesktop(number: 2, isCurrent: false, apps: ScrollingMinimapApps(pids: [2, 3], names: ["Teams", "Slack"]))]
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 360, height: scrollingMinimapRowHeight(metrics: metrics) + 68 + scrollingMinimapDesktopRowHeight))
        view.update(workspaceName: "Desktop 1", models: models, desktops: desktops, icons: [:], metrics: metrics, offset: 0, focused: models[0].id)
        let chips = view.subviews.compactMap { $0 as? ScrollingMinimapDesktopChip }
        XCTAssertEqual(chips.map(\.toolTip), ["Desktop 1 · Safari", "Desktop 2 · Teams, Slack"])
        XCTAssertGreaterThan(chips[1].frame.width, chips[0].frame.width, "A chip grows with the icons it holds")
        XCTAssertGreaterThanOrEqual(chips[1].frame.minX, chips[0].frame.maxX, "and chips do not overlap")
    }

    func testDisplaysCarryTheirDesktopNumberAndPositionFromTheRealArrangement() throws {
        let layout = observeTestDesktops([(display: "display-a", desktops: 2, active: 0), (display: "display-b", desktops: 2, active: 1)])
        _ = TestWindow.new(id: 96340, parent: layout[0][0].rootTilingContainer)
        let displays = scrollingMinimapDisplays(sortedMonitors, showing: layout[0][0])
        XCTAssertEqual(displays.map(\.desktop), [1, 4], "Numbers run across displays, as Control-N does")
        XCTAssertEqual(displays.map(\.isShown), [true, false])
        XCTAssertEqual(displays.map(\.hasWindows), [true, false])
        XCTAssertLessThan(displays[0].frame.minX, displays[1].frame.minX, "Frames keep their real places")
        XCTAssertTrue(scrollingMinimapDisplays([sortedMonitors[0]], showing: layout[0][0]).isEmpty, "One display has no arrangement to show")
    }
}

@MainActor
func minimapDescendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + minimapDescendants(of: $0) }
}

@MainActor
private final class MinimapPreviewHost: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

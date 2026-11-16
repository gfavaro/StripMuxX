@testable import AppBundle
import AppKit
import Common
import XCTest

/// Draws the overlays into bitmaps, so a regression in what they look like (blank, wrong
/// size, lost focus highlight) fails here and not on someone's screen.
@MainActor
final class OverlayRenderingTest: WorkspaceTestCase {
    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func opaquePixels(_ rep: NSBitmapImageRep, in rect: CGRect) -> Int {
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where (rep.colorAt(x: x * rep.pixelsWide / max(Int(rep.size.width), 1),
                                                                       y: y * rep.pixelsHigh / max(Int(rep.size.height), 1))?.alphaComponent ?? 0) > 0.05 { count += 1 }
        }
        return count
    }

    func testMinimapDrawsEveryTileAndTheFocusedOneStandsOut() throws {
        let workspace = focus.workspace
        let windows = (0..<5).map { TestWindow.new(id: UInt32(96100 + $0), parent: workspace.rootTilingContainer) }
        windows.forEach { $0.scrollingColumnWidth = 0.5 }
        let metrics = workspace.scrollingMetrics
        let models = windows.map { ScrollingMinimapTile(id: ObjectIdentifier($0), title: "Window", applications: [], count: 1) }
        let width = scrollingMinimapPanelWidth(metrics: metrics, maximum: 680)
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: width,
                                                      height: scrollingMinimapRowHeight(metrics: metrics) + 68))
        view.update(workspaceName: "Desktop", models: models, icons: [:], metrics: metrics,
                    offset: metrics.offsetRange.lowerBound, focused: models[2].id)
        let rep = try render(view)
        let buttons = minimapDescendants(of: view).compactMap { $0 as? ScrollingMinimapButton }
        XCTAssertEqual(buttons.count, 5)
        for button in buttons {
            let frame = view.convert(button.bounds, from: button)
            XCTAssertGreaterThan(opaquePixels(rep, in: frame), Int(frame.width * frame.height) / 3, "A tile is drawn, not blank")
        }
        // The focused tile has an accent stroke; an unfocused one has a faint neutral one.
        func edgeColor(of button: ScrollingMinimapButton) throws -> NSColor {
            let frame = view.convert(button.bounds, from: button)
            let scale = CGFloat(rep.pixelsWide) / view.bounds.width
            return try XCTUnwrap(rep.colorAt(x: Int((frame.minX + 2) * scale), y: Int(frame.midY * scale))?.usingColorSpace(.deviceRGB))
        }
        let focused = try edgeColor(of: buttons[2]), other = try edgeColor(of: buttons[4])
        XCTAssertGreaterThan(focused.blueComponent - focused.redComponent, 0.25, "Focused edge is the accent colour")
        XCTAssertGreaterThan((focused.blueComponent - focused.redComponent) - (other.blueComponent - other.redComponent), 0.15,
                             "The focused tile's edge is clearly more accent than an unfocused one")
        XCTAssertLessThanOrEqual(view.bounds.width, 680)
        XCTAssertLessThanOrEqual(buttons.map { view.convert($0.bounds, from: $0).width }.max() ?? 0,
                                 scrollingMinimapMaximumTypicalTileWidth + 1, "Compact tiles")
    }

    func testFloatingChipsAndHeaderAreDrawn() throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 96110, parent: workspace.rootTilingContainer)
        let metrics = workspace.scrollingMetrics
        let models = [ScrollingMinimapTile(id: ObjectIdentifier(window), title: "Window", applications: [], count: 1)]
        let height = scrollingMinimapRowHeight(metrics: metrics) + 68 + scrollingMinimapFloatingRowHeight
        let view = ScrollingMinimapView(frame: CGRect(x: 0, y: 0, width: 360, height: height))
        let floating = [ScrollingMinimapFloatingWindow(windowId: 1, pid: 1, title: "Calculator", focused: true)]
        view.update(workspaceName: "Desktop 1", models: models, floating: floating, icons: [:], metrics: metrics,
                    offset: 0, focused: models[0].id)
        let rep = try render(view)
        let chip = try XCTUnwrap(view.subviews.compactMap { $0 as? ScrollingMinimapFloatingChip }.first)
        XCTAssertGreaterThan(opaquePixels(rep, in: chip.frame), Int(chip.frame.width * chip.frame.height) / 3)
        XCTAssertGreaterThan(opaquePixels(rep, in: CGRect(x: 0, y: 0, width: view.bounds.width, height: 28)), 100, "Header text")
        XCTAssertGreaterThan(opaquePixels(rep, in: CGRect(x: 0, y: view.bounds.height - 26, width: view.bounds.width, height: 26)), 100, "Footer text")
    }

    func testCheatSheetDrawsEverySectionWithinItsBounds() throws {
        let rows = (0..<6).map { ShortcutCheatSheetSection.Row(keys: "⌥\($0)", action: "workspace \($0)") }
        let sections = ["Focus", "Move", "Columns", "Desktops"].map { ShortcutCheatSheetSection(title: $0, rows: rows) }
        let view = ShortcutCheatSheetView(sections: sections, maximumWidth: 1040)
        XCTAssertLessThanOrEqual(view.frame.width, 1040)
        XCTAssertLessThan(view.frame.height, 600)
        let rep = try render(view)
        XCTAssertGreaterThan(opaquePixels(rep, in: view.bounds), 4000, "Not blank")
        for (index, column) in view.columns.enumerated() {
            let x = 24 + CGFloat(index) * 324
            XCTAssertGreaterThan(opaquePixels(rep, in: CGRect(x: x, y: 50, width: 300, height: view.bounds.height - 60)), 300,
                                 "Column \(index) (\(column.map(\.title).joined(separator: ", "))) is drawn")
        }
    }
}

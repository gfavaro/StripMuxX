@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ShortcutCheatSheetTest: XCTestCase {
    func testShortcutsAreGroupedAndShownInMacOSNotation() throws {
        let parsed = parseConfig("""
        [mode.main.binding]
        alt-h = 'focus left'
        alt-shift-v = 'focus floating'
        ctrl-alt-shift-l = 'move right'
        alt-r = 'scrolling-width next'
        alt-1 = 'workspace 1'
        alt-shift-slash = 'shortcuts'
        """)
        XCTAssertEqual(parsed.errors.map(\.description), [])
        let sections = shortcutCheatSheetSections(parsed.config.modes[mainModeId])
        XCTAssertEqual(sections.map(\.title), ["Focus", "Move", "Columns", "Spaces", "Other"])
        XCTAssertEqual(sections[0].rows, [.init(keys: "⌥⇧V", action: "focus floating"), .init(keys: "⌥H", action: "focus left")])
        XCTAssertEqual(sections[1].rows, [.init(keys: "⌃⌥⇧L", action: "move right")])
        XCTAssertEqual(sections[2].rows, [.init(keys: "⌥R", action: "scrolling-width next")])
        XCTAssertEqual(sections[3].rows, [.init(keys: "⌥1", action: "workspace 1")])
        XCTAssertEqual(sections[4].rows, [.init(keys: "⌥⇧/", action: "shortcuts")])
    }

    func testSectionsFlowIntoColumnsWithoutSplittingAndFitTheWidth() {
        let rows = (0..<8).map { ShortcutCheatSheetSection.Row(keys: "⌥\($0)", action: "workspace \($0)") }
        let sections = (0..<5).map { ShortcutCheatSheetSection(title: "S\($0)", rows: rows) }
        let wide = ShortcutCheatSheetView(sections: sections, maximumWidth: 1100)
        XCTAssertEqual(wide.columns.count, 3)
        XCTAssertEqual(wide.columns.flatMap { $0 }, sections, "Every section once, in order")
        XCTAssertLessThanOrEqual(wide.frame.width, 1100)
        XCTAssertEqual(ShortcutCheatSheetView(sections: sections, maximumWidth: 360).columns.count, 1)
    }

    func testShortcutsCommandParsesAndRunsUnderNativeTiling() throws {
        XCTAssertNotNil(parseCommand("shortcuts").cmdOrNil as? ShortcutsCommand)
        XCTAssertNil(parseCommand("shortcuts now").cmdOrNil)
        XCTAssertTrue(NativeTilingCoordinator.supports(try XCTUnwrap(parseCommand("shortcuts").cmdOrNil)),
                      "Native tiling must run it")
    }
}

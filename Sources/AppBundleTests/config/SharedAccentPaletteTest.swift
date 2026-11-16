@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class SharedAccentPaletteTest: XCTestCase {
    func testBorderMinimapAndCheatSheetUseResolvedAccentColor() {
        let original = config
        defer { config = original }

        config.accentColor = "#3498DB"
        config.windowBorders.activeColor = "accent"
        let accent = winMuxEmphasisColor.usingColorSpace(.sRGB)
        XCTAssertEqual(accent?.redComponent ?? 0, 0x34 / 255.0, accuracy: 0.01)
        XCTAssertEqual(accent?.greenComponent ?? 0, 0x98 / 255.0, accuracy: 0.01)
        XCTAssertEqual(accent?.blueComponent ?? 0, 0xDB / 255.0, accuracy: 0.01)

        config.windowBorders.activeColor = "#E1E3E480"
        let override = winMuxEmphasisColor.usingColorSpace(.sRGB)
        XCTAssertEqual(override?.redComponent ?? 0, 0xE1 / 255.0, accuracy: 0.01)
        XCTAssertEqual(override?.alphaComponent ?? 0, 0x80 / 255.0, accuracy: 0.01)
        XCTAssertEqual(windowBorderRGBA(config.windowBorders.activeColor), 0xE1E3E480)
    }
}

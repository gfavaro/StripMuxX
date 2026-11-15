@testable import AppBundle
import Common
import Foundation
import XCTest

@MainActor
final class ConfigBootstrapTest: XCTestCase {
    func testBootstrapPreservesExistingUserConfig() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "stripmuxx.toml")
        let original = Data("# user configuration\nconfig-version = 2\n".utf8)
        try original.write(to: target)
        XCTAssertFalse(try materializeBootstrapConfigIfNeeded(targetUrl: target))
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testBootstrapPreservesDanglingSymlinkAndCreatesItsTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WinMuxBootstrap-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "dotfiles/stripmuxx.toml")
        let link = directory.appending(path: "stripmuxx.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertTrue(try materializeBootstrapConfigIfNeeded(targetUrl: link))

        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), starterConfigText())
    }

    func testStarterConfigParses() {
        let (parsedConfig, errors) = parseConfig(starterConfigText())
        assertEquals(errors, [])

        let bindings: [(String, String)] = parsedConfig.modes["main"]?.bindings.values.map {
            ($0.descriptionWithKeyNotation, $0.commands.prettyDescription)
        } ?? []
        let bindingMap: [String: String] = Dictionary(uniqueKeysWithValues: bindings)

        XCTAssertEqual(bindingMap["alt-h"], "focus left")
        XCTAssertEqual(bindingMap["alt-j"], "focus down")
        XCTAssertEqual(bindingMap["alt-1"], "scrolling-focus 1")
        XCTAssertEqual(bindingMap["alt-9"], "scrolling-focus last")
        XCTAssertEqual(bindingMap["alt-n"], "focus dfs-next")
        XCTAssertEqual(bindingMap["alt-shift-h"], "move left")
        XCTAssertEqual(bindingMap["cmd-shift-h"], "join-with left")
        XCTAssertEqual(bindingMap["alt-cmd-j"], "swap down")
        XCTAssertEqual(bindingMap["alt-r"], "scrolling-width next")
        XCTAssertEqual(bindingMap["alt-c"], "scrolling-center")
        XCTAssertEqual(bindingMap["cmd-shift-i"], "balance-sizes")
        XCTAssertEqual(bindingMap["ctrl-1"], "workspace 1")
        XCTAssertEqual(bindingMap["ctrl-0"], "workspace 10")
        XCTAssertEqual(bindingMap["ctrl-h"], "workspace prev")
        XCTAssertEqual(bindingMap["alt-shift-1"], "move-node-to-workspace 1")
        XCTAssertEqual(bindingMap["ctrl-shift-h"], "move-node-to-workspace --focus-follows-window prev")
        XCTAssertEqual(bindingMap["alt-shift-t"], "layout floating tiling")
        XCTAssertEqual(bindingMap["alt-shift-m"], "fullscreen")
        XCTAssertEqual(parsedConfig.ignoredConfiguration, [])
        XCTAssertTrue(parsedConfig.autoReloadConfig)
        if case .constant(let horizontalGap) = parsedConfig.gaps.inner.horizontal {
            XCTAssertEqual(horizontalGap, 8)
        } else {
            XCTFail("Expected constant horizontal gap")
        }
        if case .constant(let verticalGap) = parsedConfig.gaps.inner.vertical {
            XCTAssertEqual(verticalGap, 8)
        } else {
            XCTFail("Expected constant vertical gap")
        }
        if case .constant(let outerLeftGap) = parsedConfig.gaps.outer.left {
            XCTAssertEqual(outerLeftGap, 8, "Side gaps were tightened to 8 points")
        } else {
            XCTFail("Expected constant outer left gap")
        }
        XCTAssertEqual(parsedConfig.configVersion, 2)
    }
}

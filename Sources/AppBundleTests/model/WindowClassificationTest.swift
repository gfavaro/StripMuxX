@testable import AppBundle
import AppKit
import Common
import XCTest

final class WindowClassificationTest: XCTestCase {
    private final class Element: AxUiElementMock {
        var attributes: [String: Any] = [:]
        func containingWindowId() -> CGWindowID? { 1 }
        func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? { attributes[attr.key] as? Attr.T }

        static func window(fullscreen: Bool?, close: Bool? = true) -> Element {
            let window = Element()
            window.attributes[kAXSubroleAttribute] = kAXStandardWindowSubrole
            for (key, enabled) in [(kAXFullScreenButtonAttribute, fullscreen), (kAXCloseButtonAttribute, close)] {
                if let enabled {
                    let button = Element()
                    button.attributes[kAXEnabledAttribute] = enabled
                    window.attributes[key] = button
                }
            }
            return window
        }
    }

    func testAccessoryBundleDeclarationAcceptsSupportedPlistTypes() {
        for value: Any in [true, NSNumber(value: 1), NSNumber(value: 2), "1", "true", " TRUE "] {
            XCTAssertTrue(appDeclaresAccessory(["LSUIElement": value]), "\(value)")
        }
        for value: Any in [false, NSNumber(value: 0), "0", "false", "yes", "", NSNull(), ["invalid"]] {
            XCTAssertFalse(appDeclaresAccessory(["LSUIElement": value]), "\(value)")
        }
        XCTAssertFalse(appDeclaresAccessory(nil))
        XCTAssertFalse(appDeclaresAccessory([:]))
    }

    func testAccessoryRealWindowsFloatRegardlessOfCurrentActivationPolicy() {
        let window = Element.window(fullscreen: true)
        for policy: NSApplication.ActivationPolicy in [.regular, .accessory] {
            XCTAssertEqual(window.getWindowType(axApp: Element(), nil, policy, .normalWindow, accessory: true), .dialog)
            XCTAssertEqual(window.getWindowType(axApp: Element(), nil, policy, .normalWindow, accessory: false), .window)
        }
    }

    func testWindowsAppSessionsTileDespiteAccessoryDeclarationButDialogsFloat() {
        for policy: NSApplication.ActivationPolicy in [.regular, .accessory] {
            let session = Element.window(fullscreen: true)
            XCTAssertEqual(session.getWindowType(axApp: Element(), .windowsApp, policy, .normalWindow, accessory: true), .window)
            for fullscreen: Bool? in [nil, false] {
                let utility = Element.window(fullscreen: fullscreen)
                XCTAssertEqual(utility.getWindowType(axApp: Element(), .windowsApp, policy, .normalWindow, accessory: true), .dialog)
            }
            session.attributes[kAXSubroleAttribute] = kAXDialogSubrole
            XCTAssertEqual(session.getWindowType(axApp: Element(), .windowsApp, policy, .normalWindow, accessory: true), .dialog)
        }
    }

    func testAccessoryClassificationDoesNotPromotePopupsToFloatingWindows() {
        let window = Element.window(fullscreen: true, close: nil)
        XCTAssertEqual(window.getWindowType(axApp: Element(), nil, .accessory, .normalWindow, accessory: true), .popup)
        XCTAssertEqual(window.getWindowType(axApp: Element(), nil, .regular, .normalWindow, accessory: true), .dialog)
        let quickTerminal = Element.window(fullscreen: true)
        quickTerminal.attributes[kAXIdentifierAttribute] = "com.mitchellh.ghostty.quickTerminal"
        XCTAssertEqual(quickTerminal.getWindowType(axApp: Element(), .ghostty, .regular, .normalWindow, accessory: true), .popup)
    }

    func testUtilityWindowsFloatWithMissingOrDisabledFullscreenControls() {
        for enabled: Bool? in [nil, false, true] {
            let window = Element.window(fullscreen: enabled)
            XCTAssertEqual(window.isDialogHeuristic(.finder, .normalWindow, accessory: false), enabled != true)
            XCTAssertEqual(window.isDialogHeuristic(nil, .normalWindow, accessory: false), enabled != true)
        }
    }

    func testTitlebarOptionalApplicationsRemainTiled() {
        for app: KnownBundleId in [.alacritty, .kitty, .wezterm, .iterm2, .emacs, .qutebrowser,
                                  .vscode, .vscodium, .chrome, .activityMonitor, .gimp, .steam] {
            for enabled: Bool? in [nil, false] {
                XCTAssertFalse(Element.window(fullscreen: enabled).isDialogHeuristic(app, .normalWindow, accessory: false), app.rawValue)
            }
        }
    }

    func testGhosttyHiddenTitlebarTilesButUtilityAndQuickTerminalDoNot() {
        XCTAssertFalse(Element.window(fullscreen: nil, close: nil).isDialogHeuristic(.ghostty, .normalWindow, accessory: false))
        XCTAssertTrue(Element.window(fullscreen: false).isDialogHeuristic(.ghostty, .normalWindow, accessory: false))
        let quickTerminal = Element.window(fullscreen: true)
        quickTerminal.attributes[kAXIdentifierAttribute] = "com.mitchellh.ghostty.quickTerminal"
        XCTAssertEqual(quickTerminal.getWindowType(axApp: Element(), .ghostty, .regular, .normalWindow, accessory: false), .popup)
    }

    func testNativeDialogsFloatEvenWithFullscreenControls() {
        let dialog = Element.window(fullscreen: true)
        dialog.attributes[kAXSubroleAttribute] = kAXDialogSubrole
        XCTAssertEqual(dialog.getWindowType(axApp: Element(), nil, .regular, .normalWindow, accessory: false), .dialog)
    }

    func testSystemAuthenticationPromptsAreUnmanagedAtAnyWindowLevel() {
        let prompt = Element.window(fullscreen: nil)
        for app: KnownBundleId in [.securityAgent, .localAuthenticationUIAgent] {
            for level: MacOsWindowLevel? in [.normalWindow, .unknown(windowLevel: 1000), nil] {
                for policy: NSApplication.ActivationPolicy in [.regular, .accessory] {
                    XCTAssertEqual(prompt.getWindowType(axApp: Element(), app, policy, level, accessory: true), .popup, app.rawValue)
                }
            }
        }
    }
}

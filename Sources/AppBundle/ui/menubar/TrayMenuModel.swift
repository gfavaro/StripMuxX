import AppKit
import Common
import NativeSpaces

public final class TrayMenuModel: ObservableObject {
    @MainActor public static let shared = TrayMenuModel()

    init() {}

    @Published var modePresentation: ModePresentation?
    @Published var menuBarWorkspaceIndicator: String = "1"
    @Published var menuBarWorkspaceName: String = ""
    /// Why tiling has stopped until something outside StripMuxX changes.
    @Published var menuBarTilingStoppedReason: String? = nil
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var shortcutHealth: ShortcutHealth = .available
    @Published var menuBarConfiguration = MenuBarConfig()
}

extension ObservableObject {
    /// Assigning a @Published property fires objectWillChange even when the value is unchanged,
    /// re-rendering every observing view. Models republished on every observation must
    /// equality-guard their writes.
    /// Returns whether the value actually changed, for callers that need to chain side effects.
    @discardableResult
    func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, T>, _ value: T) -> Bool {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
            return true
        }
        return false
    }
}

/// The tray indicator: the focused display's desktop number, its name and the tiling state.
@MainActor func updateTrayText() {
    let displays = nativeObservedDisplays() ?? []
    let display = displays.first { $0.identifier == focus.workspace.workspaceMonitor.displayUUID } ?? displays.first
    let number = display.flatMap { NativeSpaceNavigation.activeDesktopNumber(on: $0.identifier, in: displays) }
    TrayMenuModel.shared.setIfChanged(\.menuBarWorkspaceIndicator, number.map(String.init) ?? "–")
    let place = display == nil ? "Spaces unavailable" : number.map { nativeDesktopDisplayName($0) } ?? "Fullscreen App"
    let tiling = runtime.native.tiling
    TrayMenuModel.shared.setIfChanged(\.menuBarWorkspaceName, "\(place) · \(tiling.status)")
    TrayMenuModel.shared.setIfChanged(\.menuBarTilingStoppedReason, tiling.isStopped ? tiling.status : nil)
}

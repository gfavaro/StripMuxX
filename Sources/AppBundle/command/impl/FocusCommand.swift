import AppKit
import Common

/// Left and right step through the strip's columns; up and down step through a stack.
struct FocusCommand: Command {
    let args: FocusCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        // A window on a desktop that is not showing: switch there first.
        if args.windowId != nil, !NativeTilingCommandScope.active {
            return try await runtime.native.focusWindowOnHiddenDesktop(args.windowId, io)
        }
        let focused = focusInStrip(env, io)
        if focused { runtime.native.focusDidMove(to: focus.windowOrNil) }
        return focused
    }

    @MainActor private func focusInStrip(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        workspace.lastScrollingFocusWindowId = nil
        switch args.target {
            case .direction(let direction):
                guard let window = target.windowOrNil, window.parent is TilingContainer else {
                    return hitStripEnd(target, io, direction)
                }
                let column = window.topLevelWorkspaceGroup
                if direction.orientation == .v {
                    let stack = (column as? TilingContainer)?.frameLayoutChildren ?? [window]
                    guard let index = stack.firstIndex(where: { $0 === window }) else { return false }
                    if let neighbor = stack.getOrNil(atIndex: index + direction.focusOffset) as? Window {
                        return neighbor.focusWindow()
                    }
                    switch args.boundariesAction {
                        case .stop: return true
                        case .fail: return false
                        case .wrapAroundTheWorkspace, .wrapAroundAllMonitors:
                            return ((direction.isPositive ? stack.first : stack.last) as? Window)?.focusWindow() ?? false
                    }
                }
                let columns = workspace.workspaceLayoutUnits
                guard let index = columns.firstIndex(where: { $0 === column }) else { return false }
                if let neighbor = columns.getOrNil(atIndex: index + direction.focusOffset)?.mostRecentWorkspaceFocusableWindowRecursive {
                    return neighbor.focusWindow()
                }
                return hitStripEnd(target, io, direction)
            case .windowId(let windowId):
                if let windowToFocus = Window.get(byId: windowId) {
                    return windowToFocus.focusWindow()
                } else {
                    return io.err("Can't find window with ID \(windowId)")
                }
            case .dfsIndex(let dfsIndex):
                if let windowToFocus = workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) {
                    return windowToFocus.focusWindow()
                } else {
                    return io.err("Can't find window with DFS index \(dfsIndex)")
                }
            case .dfsRelative(let nextPrev):
                let windows = workspace.rootTilingContainer.allLeafWindowsRecursive.filter(\.nativeLayoutEligible)
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return false
                }
                var targetIndex = switch nextPrev {
                    case .dfsNext: currentIndex + 1
                    case .dfsPrev: currentIndex - 1
                }
                if !(0 ..< windows.count).contains(targetIndex) {
                    switch args.boundariesAction {
                        case .stop: return true
                        case .fail: return false
                        case .wrapAroundTheWorkspace: targetIndex = (targetIndex + windows.count) % windows.count
                        case .wrapAroundAllMonitors: return dieT("Must be discarded by args parser")
                    }
                }
                return windows[targetIndex].focusWindow()
            case .floating:
                return focusNextFloating(after: target.windowOrNil, in: workspace, io)
        }
    }

    /// From the strip, the first floating window; from a floating window, the next one;
    /// after the last, back to the strip's most recent window.
    @MainActor private func focusNextFloating(after current: Window?, in workspace: Workspace, _ io: CmdIo) -> Bool {
        let floating = workspace.floatingWindows.sorted { $0.windowId < $1.windowId }
        guard !floating.isEmpty else { return io.err("No floating windows on this desktop") }
        guard let current, let index = floating.firstIndex(where: { $0 === current }) else {
            return floating[0].focusWindow()
        }
        if let next = floating.getOrNil(atIndex: index + 1) { return next.focusWindow() }
        return workspace.rootTilingContainer.mostRecentWorkspaceFocusableWindowRecursive?.focusWindow() ?? true
    }

    /// Past the strip's first or last column: stop, wrap, or continue onto the next display.
    @MainActor private func hitStripEnd(_ target: LiveFocus, _ io: CmdIo, _ direction: CardinalDirection) -> Bool {
        func wrapAroundTheStrip() -> Bool {
            let columns = target.workspace.workspaceLayoutUnits
            return (direction.isPositive ? columns.first : columns.last)?
                .mostRecentWorkspaceFocusableWindowRecursive?.focusWindow() ?? io.err(noWindowIsFocused)
        }
        switch args.boundaries {
            case .workspace:
                return switch args.boundariesAction {
                    case .stop: true
                    case .fail: false
                    case .wrapAroundTheWorkspace: wrapAroundTheStrip()
                    case .wrapAroundAllMonitors: dieT("Must be discarded by args parser")
                }
            case .allMonitorsOuterFrame:
                guard let (monitors, index) = target.workspace.workspaceMonitor.findRelativeMonitor(inDirection: direction) else {
                    return io.err("Should never happen. Can't find the current monitor")
                }
                if let monitor = monitors.getOrNil(atIndex: index) {
                    guard let shown = nativeActiveDesktop(on: monitor) else { return io.err("\(monitor.name) shows no desktop") }
                    return shown.focusWorkspace()
                }
                switch args.boundariesAction {
                    case .stop: return true
                    case .fail: return false
                    case .wrapAroundTheWorkspace: return wrapAroundTheStrip()
                    case .wrapAroundAllMonitors:
                        guard let wrapped = monitors.get(wrappingIndex: index), let shown = nativeActiveDesktop(on: wrapped) else { return false }
                        let columns = shown.workspaceLayoutUnits
                        (direction.isPositive ? columns.first : columns.last)?.mostRecentWindowRecursive?.markAsMostRecentChild()
                        return shown.focusWorkspace()
                }
        }
    }
}

import AppKit
import Common

func scrollingMinimapFrame(size: CGSize, visibleFrames: [CGRect], screenIndex: Int) -> CGRect? {
    guard visibleFrames.indices.contains(screenIndex - 1) else { return nil }
    let screen = visibleFrames[screenIndex - 1]
    return CGRect(x: screen.midX - size.width / 2, y: screen.minY + 32, width: size.width, height: size.height)
}

@MainActor
final class WorkspaceScrollingMinimap: NSObject {
    static let shared = WorkspaceScrollingMinimap()
    private var panel: NSPanel?
    private var view: ScrollingMinimapView?
    /// The hidden panel keeps about 4 MB of window memory; it is freed once the minimap
    /// has stayed closed a while, so a pan that reopens it right away stays instant.
    private var releaseTask: Task<Void, Never>?
    private weak var workspace: Workspace?
    private var dismissTask: Task<Void, Never>?
    private var titleTask: Task<Void, Never>?
    private var representativeIDs: [UInt32] = []
    private var icons: [Int32: NSImage] = [:]
    private var lifetime = ScrollingMinimapLifetime()
    private var generation: UInt64 = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var gestureShowTask: Task<Void, Never>?
    private weak var gestureShowWorkspace: Workspace?

    /// Shows the minimap for a gesture step after the current event has been handled, once for
    /// however many steps arrive before then.
    func showSoon(_ workspace: Workspace) {
        gestureShowWorkspace = workspace
        guard gestureShowTask == nil else { return }
        gestureShowTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.gestureShowTask = nil
            guard let workspace = self.gestureShowWorkspace else { return }
            self.gestureShowWorkspace = nil
            _ = self.show(workspace, duringGesture: true)
        }
    }

    @discardableResult
    func show(_ workspace: Workspace, duringGesture: Bool = false, explicitly: Bool = false) -> Bool {
        guard config.scrolling.minimapEnabled, workspace.isVisible, !workspace.workspaceLayoutUnits.isEmpty,
              TrayMenuModel.shared.isEnabled, NSEvent.pressedMouseButtons & 1 == 0 || duringGesture else { return false }
        guard focus.windowOrNil?.isFullscreen != true,
              focus.windowOrNil?.lastKnownNativeFullscreen != true else { dismiss(); return false }
        if isUnitTest { return true }
        if self.workspace !== workspace {
            dismiss()
            self.workspace = workspace
        }
        lifetime.activity(at: now)
        if explicitly { lifetime.openExplicitly(at: now) }
        if duringGesture { lifetime.pan(true, at: now) }
        render(workspace)
        guard self.workspace === workspace else { return false }
        panel?.alphaValue = 1
        if explicitly {
            panel?.makeKeyAndOrderFront(nil)
            view?.beginKeyboardNavigation()
        } else if panel?.isVisible != true {
            // Reordering on every pan step costs a WindowServer round trip.
            panel?.orderFrontRegardless()
        }
        scheduleDismissal()
        return true
    }

    /// `[scrolling] minimap-hold-modifiers`: holding exactly those keys keeps the
    /// minimap up over the focused desktop; releasing them lets it fade.
    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let required = config.scrolling.minimapHoldModifiers
        guard !required.isEmpty else { return }
        let held = flags.intersection([.control, .option, .command, .shift]) == required
        if held, !holding {
            holding = show(focus.workspace, duringGesture: true)
        } else if !held, holding {
            holding = false
            endGesture()
        }
    }
    private var holding = false

    func endGesture() {
        lifetime.pan(false, at: now)
        modelDidChange()
        scheduleDismissal()
    }

    func modelDidChange() {
        guard panel?.isVisible == true else { return }
        guard let workspace, workspace.isVisible, !workspace.workspaceLayoutUnits.isEmpty,
              config.scrolling.minimapEnabled, TrayMenuModel.shared.isEnabled,
              focus.windowOrNil?.isFullscreen != true,
              focus.windowOrNil?.lastKnownNativeFullscreen != true else { dismiss(); return }
        render(workspace)
    }

    func dismiss() {
        generation &+= 1
        dismissTask?.cancel()
        dismissTask = nil
        titleTask?.cancel()
        titleTask = nil
        representativeIDs = []
        icons = [:]
        lifetime = ScrollingMinimapLifetime()
        view?.resetPresentation()
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        workspace = nil
        releaseTask?.cancel()
        releaseTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard let self, self.workspace == nil, !Task.isCancelled else { return }
            self.panel?.contentView = nil
            self.panel?.close()
            self.panel = nil
            self.view = nil
            self.releaseTask = nil
        }
    }

    var isExplicitlyOpen: Bool { lifetime.isExplicitlyOpen }

    private func render(_ workspace: Workspace) {
        releaseTask?.cancel()
        releaseTask = nil
        let screens = NSScreen.screens
        let index = workspace.workspaceMonitor.monitorAppKitNsScreenScreensId
        guard screens.indices.contains(index - 1) else { dismiss(); return }
        let width = scrollingMinimapPanelWidth(metrics: workspace.scrollingMetrics,
                                               maximum: min(680, max(1, screens[index - 1].visibleFrame.width - 48)))
        let floatingWindows = workspace.floatingWindows.filter(\.nativeLayoutEligible).sorted { $0.windowId < $1.windowId }
        let height = scrollingMinimapRowHeight(metrics: workspace.scrollingMetrics) + 68
            + (floatingWindows.isEmpty ? 0 : scrollingMinimapFloatingRowHeight)
        guard let frame = scrollingMinimapFrame(size: CGSize(width: width, height: height),
            visibleFrames: screens.map(\.visibleFrame), screenIndex: index) else { dismiss(); return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // During a gesture the origin and dimensions usually do not change.
        // Avoid repeated WindowServer transactions for a stationary overlay.
        if panel.frame.size != frame.size { panel.setContentSize(frame.size) }
        if panel.frame.origin != frame.origin { panel.setFrameOrigin(frame.origin) }
        let view = self.view ?? installView(in: panel, size: frame.size)
        let targetViewFrame = CGRect(origin: .zero, size: frame.size)
        if view.frame != targetViewFrame { view.frame = targetViewFrame }
        bindSelection(of: view, to: workspace)
        let groups = workspace.scrollingStripUnits
        let pinnedColumn = workspace.pinnedScrollingColumn
        let representatives = (groups + (pinnedColumn.map { [$0] } ?? [])).compactMap(\.mostRecentWindowRecursive)
            + floatingWindows
        let models = groups.map { tile($0, in: workspace) }
        var pinned = pinnedColumn.map { tile($0, in: workspace) }
        pinned?.pinned = workspace.scrollingPinSide
        let floating = floatingWindows.map { window in
            cacheIcon(of: window.app)
            return ScrollingMinimapFloatingWindow(windowId: window.windowId, pid: window.app.pid,
                title: cachedWindowTitle(for: window) ?? window.app.name ?? "Window",
                focused: focus.windowOrNil === window)
        }
        view.update(workspaceName: userFacingDesktopName(workspace), models: models, pinned: pinned,
                    floating: floating, icons: icons,
                    metrics: workspace.scrollingMetrics, offset: workspace.scrollingOffset,
                    focused: focus.windowOrNil.flatMap { $0.nodeWorkspace === workspace ? ObjectIdentifier($0.topLevelWorkspaceGroup) : nil })
        refreshTitles(representatives, in: workspace)
    }

    /// The panel's blurred background and the minimap view in it, built once and reused.
    private func installView(in panel: NSPanel, size: CGSize) -> ScrollingMinimapView {
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.maskImage = roundedBlurMask(radius: scrollingMinimapPanelRadius)
        effect.layer?.cornerRadius = scrollingMinimapPanelRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            effect.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        let view = ScrollingMinimapView(frame: effect.bounds)
        view.autoresizingMask = [.width, .height]
        view.floatingSelected = { [weak self] id in
            guard let self, let window = Window.get(byId: id), window.focusWindow() else { return }
            runtime.native.focusDidMove(to: window)
            if let workspace = self.workspace { self.show(workspace) }
        }
        view.hoverChanged = { [weak self] hovered in
            guard let self else { return }
            self.lifetime.hover(hovered, at: self.now)
            self.panel?.alphaValue = 1
            self.scheduleDismissal()
        }
        view.dismissRequested = { [weak self] in self?.dismiss() }
        effect.addSubview(view)
        panel.contentView = effect
        panel.invalidateShadow()
        self.view = view
        return view
    }

    /// Selecting or reordering acts only while `workspace` is still the one, in the same shape,
    /// that this minimap was drawn for; a stale panel can never change another strip.
    private func bindSelection(of view: ScrollingMinimapView, to workspace: Workspace) {
        let expectedEpoch = workspace.scrollingSessionEpoch
        let expectedTopology = workspace.scrollingTopologySignature
        view.selected = { [weak self, weak workspace] id in
            guard let self, let workspace, self.workspace === workspace,
                  workspace.scrollingSessionEpoch == expectedEpoch,
                  workspace.scrollingTopologySignature == expectedTopology,
                  workspace.isVisible else { return }
            self.selectGroup(id)
        }
        view.reordered = { [weak self, weak workspace] id, index in
            guard let self, let workspace, self.workspace === workspace,
                  workspace.scrollingSessionEpoch == expectedEpoch,
                  workspace.scrollingTopologySignature == expectedTopology,
                  workspace.isVisible else { return }
            workspace.moveScrollingColumn(id, toStripIndex: index)
            self.modelDidChange()
        }
    }

    /// One column as the minimap shows it: its apps, title and, for a lone window that does not
    /// fill the column, where it really sits.
    private func tile(_ group: TreeNode, in workspace: Workspace) -> ScrollingMinimapTile {
        let windows = group.allLeafWindowsRecursive
        let window = group.mostRecentWindowRecursive
        var pids: [Int32] = []
        for member in windows where !pids.contains(member.app.pid) {
            pids.append(member.app.pid)
            cacheIcon(of: member.app)
        }
        let title = window.flatMap { member -> String? in
            cachedWindowTitle(for: member) ?? member.app.name
        } ?? "Empty column"
        // Where a lone window really sits, if it is not the column's full height.
        var vertical: ClosedRange<CGFloat> = 0...1
        let area = workspace.scrollingMetrics.geometry.area
        if windows.count == 1, let rect = windows[0].lastAppliedLayoutPhysicalRect, area.height > 1 {
            let top = min(max((rect.minY - area.minY) / area.height, 0), 0.85)
            let height = min(max(rect.height / area.height, 0.15), 1 - top)
            if top > 0.02 || height < 0.98 { vertical = top...(top + height) }
        }
        return ScrollingMinimapTile(id: ObjectIdentifier(group),
            title: title, applications: pids, count: windows.count,
            freeSize: windows.count == 1 && windows[0].freeSizeRect != nil, vertical: vertical)
    }

    private func cacheIcon(of app: any AbstractApp) {
        guard icons[app.pid] == nil else { return }
        icons[app.pid] = (app as? MacApp)?.nsApp.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
    }

    private func refreshTitles(_ windows: [Window], in workspace: Workspace) {
        let windows = Array(windows.prefix(32))
        let ids = windows.map(\.windowId)
        guard representativeIDs != ids else { return }
        representativeIDs = ids
        titleTask?.cancel()
        let expected = generation
        titleTask = Task { @MainActor [weak self, weak workspace] in
            for window in windows {
                guard !Task.isCancelled, self?.generation == expected else { return }
                _ = await getSessionWindowTitle(window)
            }
            guard !Task.isCancelled, let self, let workspace, self.generation == expected,
                  self.workspace === workspace else { return }
            self.titleTask = nil
            self.modelDidChange()
        }
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.alphaValue = 1
        guard workspace != nil, let delay = lifetime.dismissalDelay(at: now) else { return }
        let expected = generation
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.generation == expected, !Task.isCancelled,
                  self.lifetime.dismissalDelay(at: self.now) == 0 else { return }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                for step in 1...8 {
                    guard !Task.isCancelled, self.generation == expected else { return }
                    self.panel?.alphaValue = 1 - CGFloat(step) / 8
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                }
            }
            guard !Task.isCancelled, self.generation == expected else { return }
            self.dismiss()
        }
    }

    private func selectGroup(_ id: ObjectIdentifier) {
        guard let workspace, focusScrollingMinimapGroup(id, in: workspace) else { dismiss(); return }
        show(workspace)
    }

    private func makePanel() -> NSPanel {
        let panel = ScrollingMinimapPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "Scrolling workspace minimap"
        panel.identifier = NSUserInterfaceItemIdentifier("WinMux.scrollingMinimap")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        return panel
    }
}

@MainActor
private final class ScrollingMinimapPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

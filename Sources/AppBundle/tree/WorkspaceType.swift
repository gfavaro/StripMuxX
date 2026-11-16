import AppKit
import Common

/// The strip of one macOS desktop: its columns under `rootTilingContainer`, its floating
/// windows as direct children, and where the strip is scrolled to.
final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let id: WorkspaceId
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments
    var preferredMonitorPoint: CGPoint? {
        didSet { if oldValue != preferredMonitorPoint { scrollingSessionEpoch &+= 1 } }
    }
    var scrollingSessionEpoch: UInt64 = 0
    var scrollingOffset: CGFloat = 0
    /// While a gesture eases the windows toward `scrollingOffset` (`ScrollingViewportEaser`), the
    /// offset the layout places them by. Nil everywhere else: the layout then uses the real one.
    var scrollingRenderedOffset: CGFloat?
    /// Preserve a restored viewport until the first focused window is observed.
    /// Focus reconciliation must not immediately erase the saved camera position.
    var scrollingRestoredViewportPending = false
    /// A column held at a screen edge, full height, while the rest of the strip scrolls.
    weak var scrollingPinnedNode: TreeNode?
    var scrollingPinSide = ScrollingPinCmdArgs.Side.left
    var lastScrollingFocusWindowId: UInt32?
    /// Weak identities prevent a recycled WindowServer ID from inheriting old
    /// focus history. These are hints only; native macOS focus still wins.
    weak var lastFocusedWindow: Window?
    weak var previousFocusedWindow: Window?
    /// Where the strip was before an attached sheet pulled it aside, to settle back.
    var scrollingSheetReveal: ScrollingSheetReveal?
    var scrollingAnchorWindowId: UInt32?
    var scrollingAnchorViewportPosition: CGFloat?
    var scrollingAnchorAreaWidth: CGFloat?
    /// Last observed logical center of the anchored column in strip coordinates.
    /// Inserting/removing earlier columns changes this even if the screen width does not.
    var scrollingAnchorLogicalCenter: CGFloat?
    @MainActor var scrollingGestureMotionActive = false
    @MainActor var scrollingGestureSessionID: UUID?

    @MainActor
    private init(_ name: String) {
        self.id = runtime.workspaces.nextWorkspaceId()
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] {
        runtime.workspaces.sortedWorkspaces()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = runtime.workspaces.workspace(named: name) {
            return existing
        } else {
            let workspace = Workspace(name)
            runtime.workspaces.registerWorkspace(workspace)
            return workspace
        }
    }

    @MainActor static func existing(byName name: String) -> Workspace? {
        runtime.workspaces.workspace(named: name)
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        "Workspace(id: '\(id.rawValue)', name: '\(name)', isVisible: '\(isVisible)', isEffectivelyEmpty: '\(isEffectivelyEmpty)')"
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

}

extension Workspace {
    @MainActor
    var scrollingTopologySignature: String {
        let bounds = workspaceTilingRect(self)
        var values: [String] = [id.rawValue, "\(bounds.minX),\(bounds.minY),\(bounds.width),\(bounds.height)"]
        func visit(_ node: TreeNode) {
            values.append("\(ObjectIdentifier(node).hashValue):\(node.bindingGeneration):\(node.children.count):\(node.scrollingColumnWidth ?? config.scrolling.columnWidth):\(node.scrollingColumnFixedWidth ?? 0)")
            if let window = node as? Window {
                values.append("\(window.minimumLayoutSize.width),\(window.minimumLayoutSize.height)")
            }
            node.children.forEach(visit)
        }
        visit(rootTilingContainer)
        return values.joined(separator: ",")
    }
}

extension Workspace {
    /// The desktop is the one its display shows.
    @MainActor
    var isVisible: Bool {
        runtime.workspaces.monitorViewportsById.values.contains { $0.activeWorkspaceId == id }
    }

    @MainActor
    var assignedMonitor: Monitor? {
        visibleMonitor ?? preferredMonitorPoint?.monitorApproximation
    }

    @MainActor
    var workspaceMonitor: Monitor {
        assignedMonitor ?? mainMonitor
    }

    @MainActor
    var visibleMonitor: Monitor? {
        runtime.workspaces.monitorViewportsById.first { _, viewport in
            viewport.activeWorkspaceId == id
        }?.key.topLeftCorner.monitorApproximation
    }
}

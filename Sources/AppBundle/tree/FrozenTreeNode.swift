import AppKit
import Common

enum FrozenTreeNode: Codable, Equatable, Sendable {
    case container(FrozenContainer)
    case window(FrozenWindow)
}

/// A strip, or a stack within it, as saved. Files written before the strip-only layout
/// carry more fields; they are ignored, and `restoreStrip` reshapes what they describe.
struct FrozenContainer: Codable, Equatable, Sendable {
    var children: [FrozenTreeNode]
    let orientation: Orientation
    let weight: CGFloat
    let scrollingColumnWidth: CGFloat?
    let scrollingColumnFixedWidth: CGFloat?

    @MainActor init(_ container: TilingContainer) {
        children = container.children.map {
            switch $0.nodeCases {
                case .window(let w): .window(FrozenWindow(w))
                case .tilingContainer(let c): .container(FrozenContainer(c))
                case .workspace: illegalChildParentRelation(child: $0, parent: container)
            }
        }
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
        scrollingColumnWidth = container.scrollingColumnWidth
        scrollingColumnFixedWidth = container.scrollingColumnFixedWidth
    }

    var windows: [FrozenWindow] {
        children.flatMap { child -> [FrozenWindow] in
            switch child {
                case .window(let window): [window]
                case .container(let container): container.windows
            }
        }
    }
}

struct FrozenWindow: Codable, Equatable, Sendable {
    let id: UInt32
    let restartIdentity: RestartWindowIdentity?
    let weight: CGFloat
    let isFullscreen: Bool
    let noOuterGapsInFullscreen: Bool
    let learnedMinimumSize: CGSize?
    let minimumEvidenceVersion: Int
    let minimumEvidenceBundleId: String?
    let minimumEvidenceGlobalGeneration: UInt64
    let minimumEvidenceAppGeneration: UInt64
    let lastFloatingSize: CGSize?
    let singleWindowManualWidth: CGFloat?
    let scrollingColumnWidth: CGFloat?
    let scrollingColumnFixedWidth: CGFloat?

    @MainActor init(_ window: Window) {
        id = window.windowId
        restartIdentity = window.restartIdentity
        weight = getWeightOrNil(window) ?? 1
        isFullscreen = window.isFullscreen
        noOuterGapsInFullscreen = window.noOuterGapsInFullscreen
        lastFloatingSize = window.parent is Workspace && !window.isFullscreen
            ? window.lastKnownActualRect?.size ?? window.lastFloatingSize : window.lastFloatingSize
        singleWindowManualWidth = window.singleWindowManualWidth
        scrollingColumnWidth = window.scrollingColumnWidth
        scrollingColumnFixedWidth = window.scrollingColumnFixedWidth
        minimumEvidenceVersion = 3
        let minimum = window as? MacWindow
        learnedMinimumSize = minimum?.learnedMinimum.size == .zero ? nil : minimum?.learnedMinimum.size
        minimumEvidenceBundleId = minimum?.macApp.rawAppBundleId
        let generation = PersistedAppMinimums.shared.evidenceGeneration(for: minimum?.macApp.rawAppBundleId)
        minimumEvidenceGlobalGeneration = generation.global
        minimumEvidenceAppGeneration = generation.app
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case restartIdentity
        case weight
        case isFullscreen
        case noOuterGapsInFullscreen
        case learnedMinimumSize
        case minimumEvidenceVersion
        case minimumEvidenceBundleId
        case minimumEvidenceGlobalGeneration
        case minimumEvidenceAppGeneration
        case lastFloatingSize
        case singleWindowManualWidth
        case scrollingColumnWidth
        case scrollingColumnFixedWidth
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt32.self, forKey: .id)
        restartIdentity = try container.decodeIfPresent(RestartWindowIdentity.self, forKey: .restartIdentity)
        weight = try container.decode(CGFloat.self, forKey: .weight)
        isFullscreen = try container.decode(Bool.self, forKey: .isFullscreen)
        noOuterGapsInFullscreen = try container.decode(Bool.self, forKey: .noOuterGapsInFullscreen)
        minimumEvidenceVersion = try container.decodeIfPresent(Int.self, forKey: .minimumEvidenceVersion) ?? 1
        learnedMinimumSize = minimumEvidenceVersion == 2
            || minimumEvidenceVersion == 3
            ? try container.decodeIfPresent(CGSize.self, forKey: .learnedMinimumSize) : nil
        minimumEvidenceBundleId = try container.decodeIfPresent(String.self, forKey: .minimumEvidenceBundleId)
        minimumEvidenceGlobalGeneration = try container.decodeIfPresent(UInt64.self, forKey: .minimumEvidenceGlobalGeneration) ?? 0
        minimumEvidenceAppGeneration = try container.decodeIfPresent(UInt64.self, forKey: .minimumEvidenceAppGeneration) ?? 0
        lastFloatingSize = try container.decodeIfPresent(CGSize.self, forKey: .lastFloatingSize)
        singleWindowManualWidth = try container.decodeIfPresent(CGFloat.self, forKey: .singleWindowManualWidth)
        scrollingColumnWidth = try container.decodeIfPresent(CGFloat.self, forKey: .scrollingColumnWidth)
        scrollingColumnFixedWidth = try container.decodeIfPresent(CGFloat.self, forKey: .scrollingColumnFixedWidth)
    }
}

@MainActor private func getWeightOrNil(_ node: TreeNode) -> CGFloat? {
    ((node.parent as? TilingContainer)?.orientation).map { node.getWeight($0) }
}

extension FrozenTreeNode {
    private enum CodingKeys: String, CodingKey {
        case kind
        case container
        case window
    }

    private enum Kind: String, Codable {
        case container
        case window
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
            case .container:
                self = .container(try container.decode(FrozenContainer.self, forKey: .container))
            case .window:
                self = .window(try container.decode(FrozenWindow.self, forKey: .window))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .container(let frozenContainer):
                try container.encode(Kind.container, forKey: .kind)
                try container.encode(frozenContainer, forKey: .container)
            case .window(let frozenWindow):
                try container.encode(Kind.window, forKey: .kind)
                try container.encode(frozenWindow, forKey: .window)
        }
    }
}

/// A desktop's strip and floating windows, to restore later onto the windows it names.
struct FrozenStrip: Codable, Equatable, Sendable {
    let root: FrozenContainer
    let floating: [FrozenWindow]
    /// A window of the pinned column, and its side.
    var pinnedWindowID: UInt32? = nil
    var pinSide: ScrollingPinCmdArgs.Side? = nil
    /// Optional for backwards compatibility with existing v1 native layout files.
    var scrollingOffset: CGFloat? = nil

    @MainActor init(_ workspace: Workspace) {
        root = FrozenContainer(workspace.rootTilingContainer)
        floating = workspace.floatingWindows.map(FrozenWindow.init)
        pinnedWindowID = workspace.pinnedScrollingColumn?.mostRecentWindowRecursive?.windowId
        pinSide = pinnedWindowID == nil ? nil : workspace.scrollingPinSide
        scrollingOffset = workspace.scrollingOffset.isFinite ? workspace.scrollingOffset : nil
    }

    var windows: [FrozenWindow] { root.windows + floating }
}

/// Rebuilds a workspace's strip from a saved one. `windowsById` maps saved window IDs to
/// the windows that now stand for them; saved windows without one are skipped, and
/// tiled windows the saved strip does not name are appended as columns.
@MainActor
func restoreStrip(_ frozen: FrozenStrip, to workspace: Workspace, windowsById: [UInt32: Window]) {
    let previous = workspace.rootTilingContainer
    previous.unbindFromParent()
    let root = workspace.rootTilingContainer
    for column in frozen.root.children {
        switch column {
            case .window(let saved):
                guard let window = windowsById[saved.id] else { continue }
                applyFrozenWindowState(window, saved)
                window.bind(to: root, adaptiveWeight: saved.weight, index: INDEX_BIND_LAST)
            case .container(let saved):
                let stack = TilingContainer(parent: root, adaptiveWeight: saved.weight, .v, index: INDEX_BIND_LAST)
                stack.scrollingColumnWidth = saved.scrollingColumnWidth
                stack.scrollingColumnFixedWidth = saved.scrollingColumnFixedWidth
                for member in saved.windows {
                    guard let window = windowsById[member.id] else { continue }
                    applyFrozenWindowState(window, member)
                    window.bind(to: stack, adaptiveWeight: member.weight, index: INDEX_BIND_LAST)
                }
        }
    }
    for saved in frozen.floating {
        guard let window = windowsById[saved.id] else { continue }
        applyFrozenWindowState(window, saved)
        // Floating windows keep their actual frame; only the tree changes.
        window.bind(to: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    for column in previous.children {
        column.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    workspace.scrollingPinnedNode = frozen.pinnedWindowID.flatMap { windowsById[$0] }?.topLevelWorkspaceGroup
    workspace.scrollingPinSide = frozen.pinSide ?? .left
    workspace.normalizeContainers()
    // Restore the viewport with its desktop rather than restarting at the first column.
    // The next layout pass clamps this value against the current display geometry.
    workspace.scrollingOffset = frozen.scrollingOffset.flatMap { $0.isFinite ? $0 : nil } ?? 0
    workspace.scrollingRestoredViewportPending = frozen.scrollingOffset?.isFinite == true
    workspace.lastScrollingFocusWindowId = nil
}

@MainActor
func applyFrozenWindowState(_ window: Window, _ frozenWindow: FrozenWindow) {
    window.scrollingColumnWidth = frozenWindow.scrollingColumnWidth
    window.scrollingColumnFixedWidth = frozenWindow.scrollingColumnFixedWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    window.isFullscreen = frozenWindow.isFullscreen
    window.noOuterGapsInFullscreen = frozenWindow.noOuterGapsInFullscreen
    (window as? MacWindow)?.restoreLearnedMinimum(
        frozenWindow.learnedMinimumSize,
        savedBundleId: frozenWindow.minimumEvidenceBundleId,
        generation: MinimumEvidenceGeneration(global: frozenWindow.minimumEvidenceGlobalGeneration,
                                              app: frozenWindow.minimumEvidenceAppGeneration)
    )
    if let size = frozenWindow.lastFloatingSize, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 {
        window.lastFloatingSize = size
    }
    if let width = frozenWindow.singleWindowManualWidth, width.isFinite, width > 0 {
        window.singleWindowManualWidth = width
    }
}

import AppKit
import Common

private let traceTreeBindings = ProcessInfo.processInfo.environment["STRIPMUXX_TRACE_TREE_BINDINGS"] == "1"

open class TreeNode: Equatable, WinMuxAny {
    private(set) var bindingGeneration: UInt64 = 0
    private var _children: [TreeNode] = []
    var children: [TreeNode] { _children }
    fileprivate final weak var _parent: NonLeafTreeNodeObject? = nil
    final var parent: NonLeafTreeNodeObject? { _parent }
    private var adaptiveWeight: CGFloat
    private let _mruChildren: MruStack<TreeNode> = MruStack()
    /// Where the last layout put this node on the strip, as if it were not clipped to the display.
    var lastAppliedLayoutVirtualRect: Rect? = nil
    /// The frame the last layout asked for, on screen.
    var lastAppliedLayoutPhysicalRect: Rect? = nil
    /// A column's own width as a share of the viewport; nil uses `[scrolling] column-width`.
    var scrollingColumnWidth: CGFloat? = nil
    final var unboundStacktrace: String? = nil
    var isBound: Bool { parent != nil } // todo drop, once https://github.com/nikitabobko/WinMux/issues/1215 is fixed

    @MainActor
    init(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.adaptiveWeight = adaptiveWeight
        bind(to: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    fileprivate init() {
        adaptiveWeight = 0
    }

    /// See: ``getWeight(_:)``
    func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        guard let parent else { die("Can't change weight if TreeNode doesn't have parent") }
        switch getChildParentRelation(child: self, parent: parent) {
            case .tiling(let parent):
                if parent.orientation != targetOrientation {
                    die("You can't change \(targetOrientation) weight of nodes located in \(parent.orientation) container")
                }
                adaptiveWeight = newValue
            default:
                die("Can't change weight")
        }
    }

    /// Weight itself doesn't make sense. The parent container controls semantics of weight
    @MainActor
    func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        guard let parent else { die("Weight doesn't make sense for containers without parent") }
        return switch getChildParentRelation(child: self, parent: parent) {
            case .tiling(let parent):
                parent.orientation == targetOrientation ? adaptiveWeight : parent.getWeight(targetOrientation)
            case .rootTilingContainer: parent.getWeight(targetOrientation)
            case .floatingWindow: dieT("Weight doesn't make sense for floating windows")
        }
    }

    @MainActor
    @discardableResult
    func bind(to newParent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) -> BindingData? {
        bindingGeneration &+= 1
        let result = unbindIfBound()

        if newParent === NilTreeNode.instance {
            return result
        }
        let relation = getChildParentRelation(child: self, parent: newParent) // Side effect: verify relation
        if adaptiveWeight == WEIGHT_AUTO {
            self.adaptiveWeight = switch relation {
                case .tiling(let newParent):
                    CGFloat(newParent.children.sumOfDouble { $0.getWeight(newParent.orientation) }).div(newParent.children.count) ?? 1
                case .floatingWindow, .rootTilingContainer: WEIGHT_DOESNT_MATTER
            }
        } else {
            self.adaptiveWeight = adaptiveWeight
        }
        let insertionIndex = index != INDEX_BIND_LAST ? index : newParent._children.count
        newParent._children.insert(self, at: insertionIndex)
        _parent = newParent
        unboundStacktrace = nil
        // todo consider disabling automatic mru propogation
        // 1. "floating windows" in FocusCommand break the MRU because of that :(
        // 2. Misbehaved apps that abuse real window as popups https://github.com/nikitabobko/WinMux/issues/106 (the
        //    last appeared window, is not necessarily the one that has the focus)
        markAsMostRecentChild()
        return result
    }

    private func unbindIfBound() -> BindingData? {
        guard let _parent else { return nil }

        let index = _parent._children.firstIndex(of: self) ?? dieT("Can't find child in its parent")
        _parent._children.remove(at: index)
        check(_parent._mruChildren.remove(self))
        self._parent = nil
        unboundStacktrace = traceTreeBindings ? getStringStacktrace() : nil

        return BindingData(parent: _parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    func markAsMostRecentChild() {
        guard let _parent else { return }
        _parent._mruChildren.pushOrRaise(self)
        _parent.markAsMostRecentChild()
    }

    var mostRecentChild: TreeNode? { _mruChildren.mostRecent ?? children.last }

    var childrenByMostRecentUse: [TreeNode] {
        var result = Array(_mruChildren)
        for child in _children.reversed() where !result.contains(child) {
            result.append(child)
        }
        return result
    }

    @discardableResult
    func unbindFromParent() -> BindingData {
        unbindIfBound() ?? dieT("\(self) is already unbound. The stacktrace where it was unbound:\n\(unboundStacktrace ?? "nil")")
    }

    nonisolated public static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs === rhs
    }

}

let WEIGHT_DOESNT_MATTER = CGFloat(-2)
/// Splits containers evenly if tiling.
///
/// Reset weight is bind to workspace (aka "floating windows")
let WEIGHT_AUTO = CGFloat(-1)

let INDEX_BIND_LAST = -1

struct BindingData {
    let parent: NonLeafTreeNodeObject
    let adaptiveWeight: CGFloat
    let index: Int
}

final class NilTreeNode: TreeNode, NonLeafTreeNodeObject {
    override private init() {
        super.init()
    }
    @MainActor static let instance = NilTreeNode()
}

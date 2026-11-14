@testable import AppBundle
import AppKit

extension TilingContainer {
    /// A stack column at the end of the strip.
    @MainActor
    static func newStack(in workspace: Workspace) -> TilingContainer {
        TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .v, index: INDEX_BIND_LAST)
    }
}

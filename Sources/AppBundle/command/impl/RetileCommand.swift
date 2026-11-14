import AppKit
import Common

/// Counts the tiled windows on showing desktops that are off their tiles, then lets the
/// read requested once a command completes put them back. The put-back budget is renewed,
/// so windows it had given up on are tried again.
struct RetileCommand: Command {
    let args: RetileCmdArgs
    /// Where WindowServer has a window; tests replace it.
    @MainActor static var frame: (UInt32) -> CGRect? = windowServerFrame

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let candidates = retileCandidates(frame: Self.frame)
        // A layout pass skips windows left alone on their tile; these are off it.
        for window in candidates { window.lastAppliedLayoutPhysicalRect = nil }
        let moved = candidates.count
        NativeFrameRecovery.shared.reset()
        let message = moved == 0 ? "Nothing had moved" : "Put \(moved) \(moved == 1 ? "window" : "windows") back"
        NoticePanel.shared.show(title: "Retile", body: message, seconds: 1.5)
        return io.out(message)
    }
}

/// Tiled windows on showing desktops that do not rest on their tiles.
@MainActor
func retileCandidates(frame: (UInt32) -> CGRect?) -> [Window] {
    Workspace.all.filter(\.isVisible).flatMap(\.allLeafWindowsRecursive).filter { window in
        guard window.parent is TilingContainer, !window.isFullscreen, !window.isConcealedByScrolling,
              let tile = window.lastAppliedLayoutPhysicalRect, let actual = frame(window.windowId) else { return false }
        return !windowRestsOnTile(actual, tile: tile)
    }
}

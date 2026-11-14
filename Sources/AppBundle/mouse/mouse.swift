import AppKit

/// The pointer in top-left screen coordinates; see `monitorFrameNormalized`.
var mouseLocation: CGPoint {
    normalizeAppKitScreenPoint(NSEvent.mouseLocation)
}

func normalizeAppKitScreenPoint(_ point: CGPoint) -> CGPoint {
    point.copy(\.y, mainMonitor.height - point.y)
}

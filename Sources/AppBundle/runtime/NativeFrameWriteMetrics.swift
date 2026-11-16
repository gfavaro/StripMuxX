import Foundation

/// Counts frame targets at the window boundary without altering AX behavior.
/// These counters are diagnostic, not a deduplication or success signal.
@MainActor
final class NativeFrameWriteMetrics {
    static let shared = NativeFrameWriteMetrics()
    private init() {}
    var requests: UInt64 = 0
    var gestureRequests: UInt64 = 0
    var normalRequests: UInt64 = 0
    var repeatedTargets: UInt64 = 0
    /// Gesture steps whose frame equalled the window's previous one in the same gesture.
    var gestureSkipped: UInt64 = 0
}

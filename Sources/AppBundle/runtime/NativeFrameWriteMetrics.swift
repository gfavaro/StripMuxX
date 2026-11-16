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

/// How long the apps take to apply gesture frame writes. Written from the per-app AX
/// threads, so it has its own lock. Diagnostic only.
final class AxWriteTiming: @unchecked Sendable {
    static let shared = AxWriteTiming()
    private let lock = NSLock()
    private var count = 0
    private var total = 0.0
    private var maximum = 0.0
    private var slowest: [String: (count: Int, total: Double, max: Double)] = [:]

    func record(_ milliseconds: Double, app: String) {
        lock.lock(); defer { lock.unlock() }
        count += 1; total += milliseconds; maximum = max(maximum, milliseconds)
        var entry = slowest[app] ?? (0, 0, 0)
        entry.count += 1; entry.total += milliseconds; entry.max = max(entry.max, milliseconds)
        slowest[app] = entry
    }

    var summary: String {
        lock.lock(); defer { lock.unlock() }
        guard count > 0 else { return "no gesture writes yet" }
        let apps = slowest.sorted { $0.value.total / Double($0.value.count) > $1.value.total / Double($1.value.count) }.prefix(4)
            .map { "\($0.key) \(String(format: "%.1f", $0.value.total / Double($0.value.count))) ms" }.joined(separator: ", ")
        return "\(count) writes, avg \(String(format: "%.1f", total / Double(count))) ms, max \(String(format: "%.0f", maximum)) ms; slowest apps: \(apps)"
    }
}

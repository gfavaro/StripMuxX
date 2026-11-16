import AppKit
import Common

/// Records a real gesture for analysis: every input step, and where every on-screen window
/// and StripMuxX border piece is, on one clock. Synthetic events cannot stand in for a
/// three-finger swipe, so this is how those get measured on a trackpad.
/// `debug-windows --gesture-trace-start`, swipe, `--gesture-trace-stop` writes a JSON file.
@MainActor
final class GestureTrace {
    static let shared = GestureTrace()
    private(set) var running = false
    private var startedAt: UInt64 = 0
    private var inputs: [[String: Any]] = []
    private var sampler: TraceSampler?
    private var autoStop: Task<Void, Never>?
    /// What `--gesture-trace-stop` prints for a trace that stopped by itself, until it is collected.
    private var finishedAlone: String?

    nonisolated static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    func start(io: CmdIo, stopsAfter limit: Duration = .seconds(120)) -> Bool {
        guard !running else { return io.err("A gesture trace is already running; use --gesture-trace-stop") }
        startedAt = Self.now()
        running = true
        inputs = []
        let sampler = TraceSampler(startedAt: startedAt)
        self.sampler = sampler
        Thread.detachNewThread { sampler.run() }
        finishedAlone = nil
        autoStop = Task { @MainActor [weak self] in
            try? await Task.sleep(for: limit)
            guard let self, self.running else { return }
            if case .saved(let report) = self.finish() { self.finishedAlone = report }
        }
        io.out("Gesture trace started. Do your gestures now, then run: stripmuxx debug-windows --gesture-trace-stop (it stops by itself after 120 s and keeps what it recorded).")
        return true
    }

    /// One input step: `kind` is pan, dock or end; `delta` the finger movement in points.
    func note(_ kind: String, delta: Double = 0, from: CGFloat? = nil, offset: CGFloat = 0) {
        guard running else { return }
        var step: [String: Any] = ["t": Double(Self.now() - startedAt) / 1e6, "kind": kind, "delta": delta, "offset": Double(offset)]
        if let from { step["from"] = Double(from) }
        inputs.append(step)
    }

    func stop(io: CmdIo) -> Bool {
        if !running, let report = finishedAlone {
            finishedAlone = nil
            return io.out(report)
        }
        switch finish() {
            case .saved(let report): return io.out(report)
            case .notRunning: return io.err("No gesture trace is running")
            case .failed: return io.err("Could not write the trace")
        }
    }

    private enum Outcome {
        case saved(String), notRunning, failed
    }

    /// Ends the trace and writes it out; the report is the file's path and a one-line summary.
    private func finish() -> Outcome {
        guard running, let sampler else { return .notRunning }
        running = false
        autoStop?.cancel()
        sampler.stop()
        self.sampler = nil
        let changes = sampler.changes
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stripmuxx-gesture-trace-\(UUID().uuidString).json")
        let seconds = Double(Self.now() - startedAt) / 1e9
        let document: [String: Any] = [
            "seconds": seconds, "inputs": inputs, "windowChanges": changes,
            "note": "t is milliseconds since the trace started. windowChanges rows: [t, windowId, owner, x, y, width, height].",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: document),
              (try? data.write(to: url)) != nil else { return .failed }
        return .saved("\(url.path)\n\(inputs.count) input steps, \(changes.count) window position changes over \(String(format: "%.1f", seconds)) s")
    }
}

/// Polls the window server off the main thread and keeps only changes.
private final class TraceSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var rows: [[Any]] = []
    private var last: [Int: [Double]] = [:]
    private let startedAt: UInt64

    init(startedAt: UInt64) { self.startedAt = startedAt }

    func stop() { lock.withLock { active = false } }
    var changes: [[Any]] { lock.withLock { rows } }

    func run() {
        while lock.withLock({ active }) {
            let t = Double(GestureTrace.now() - startedAt) / 1e6
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            var batch: [[Any]] = []
            for window in list {
                guard (window[kCGWindowLayer as String] as? Int) == 0,
                      let id = window[kCGWindowNumber as String] as? Int,
                      let bounds = window[kCGWindowBounds as String] as? [String: Double],
                      let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"],
                      w > 3, h > 3 else { continue }
                let frame = [x, y, w, h]
                if last[id] == frame { continue }
                last[id] = frame
                batch.append([t, id, window[kCGWindowOwnerName as String] as? String ?? "", x, y, w, h])
            }
            if !batch.isEmpty { lock.withLock { rows.append(contentsOf: batch) } }
            usleep(3000)
        }
    }
}

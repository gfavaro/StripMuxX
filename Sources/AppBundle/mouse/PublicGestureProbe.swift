import AppKit
import Common

/// Non-invasive public-API experiment. Never installs a touch driver, never
/// intercepts ordinary two-finger scrolling and never attempts to infer finger
/// count from CG scroll fields.
@MainActor
final class PublicGestureProbe {
    static let shared = PublicGestureProbe()

    struct Counters {
        var cgScrollTotal = 0
        var cgHorizontalContinuous = 0
        var cgHorizontalPlain = 0
        var cgHorizontalOption = 0
        var cgVerticalContinuous = 0
        var cgMomentum = 0
        var appKitSwipe = 0
        var appKitGesture = 0
        var appKitScroll = 0
        var largestPlainHorizontalDelta: CGFloat = 0
    }

    private(set) var running = false
    private(set) var counters = Counters()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var startTime: TimeInterval = 0

    func start(io: CmdIo) -> Bool {
        guard !running else { return io.err("Gesture probe already running; use --gesture-probe-stop") }
        counters = Counters()
        startTime = ProcessInfo.processInfo.systemUptime
        // Global AppKit monitoring is strictly observational; it cannot suppress
        // navigation gestures or reroute them away from the foreground application.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.swipe, .gesture, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.observeAppKit(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe, .gesture, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.observeAppKit(event) }
            return event
        }
        running = true
        io.out("Public gesture probe started. While another app is focused: perform horizontal two-finger scroll, then three-finger swipe, then four-finger Space switch. Finish with stripmuxx debug-windows --gesture-probe-stop. No input is blocked.")
        return true
    }

    func stop(io: CmdIo) -> Bool {
        guard running else { return io.err("Gesture probe is not running") }
        running = false
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startTime)
        io.out(report(elapsed: elapsed))
        return true
    }

    /// This uses the existing event tap (only while an explicit probe is running).
    /// CGEvent fields describe scroll delta and phases, NOT number of fingers.
    func observeCGScroll(_ event: NativeScrollingPan.Scroll) {
        guard running else { return }
        counters.cgScrollTotal += 1
        if event.momentumPhase != 0 { counters.cgMomentum += 1 }
        guard event.isContinuous else { return }
        if abs(event.deltaX) > abs(event.deltaY) {
            counters.cgHorizontalContinuous += 1
            if event.optionOnly {
                counters.cgHorizontalOption += 1
            } else {
                counters.cgHorizontalPlain += 1
                counters.largestPlainHorizontalDelta = max(counters.largestPlainHorizontalDelta, abs(event.deltaX))
            }
        } else if abs(event.deltaY) > 0 {
            counters.cgVerticalContinuous += 1
        }
    }

    private func observeAppKit(_ event: NSEvent) {
        guard running else { return }
        switch event.type {
            case .swipe: counters.appKitSwipe += 1
            case .gesture: counters.appKitGesture += 1
            case .scrollWheel: counters.appKitScroll += 1
            default: break
        }
    }

    func report(elapsed: TimeInterval) -> String {
        let c = counters
        return """
        Public gesture probe completed (\(String(format: "%.1f", elapsed)) seconds).
        Existing CGEventTap scroll observations:
          total: \(c.cgScrollTotal)
          horizontal continuous: \(c.cgHorizontalContinuous) (plain \(c.cgHorizontalPlain), Option \(c.cgHorizontalOption))
          vertical continuous: \(c.cgVerticalContinuous); momentum: \(c.cgMomentum)
          max plain horizontal delta: \(String(format: "%.2f", Double(c.largestPlainHorizontalDelta)))
        Public NSEvent local/global monitor observations:
          swipe: \(c.appKitSwipe); gesture: \(c.appKitGesture); scrollWheel: \(c.appKitScroll)
        Interpretation: counts alone CANNOT distinguish two from three fingers.
        Swipe/gesture events may not be delivered to global monitors on this macOS.
        No touch data was captured. No events were consumed by this probe.
        """
    }
}

import AppKit
import Common

// Experimental native swipe recognition adapted from WinMuxX's DockWorkspaceSwipe.
// macOS recognizes three fingers; event arbitration uses private Dock event fields.
// Only horizontal Dock swipes are claimed. Vertical swipes remain macOS-owned.
// No background touch collection or raw multitouch framework.
enum StripDockSwipeStart: Equatable {
    /// WinMuxX previews and may act.
    case started
    /// WinMuxX owns the swipe but does nothing with it (Option held, a switch settling).
    case ignored
    /// Nothing for WinMuxX that way, or WinMuxX is not taking swipes: macOS gets the swipe.
    case unavailable
}

@MainActor
protocol StripDockSwipeReceiver: AnyObject {
    /// Asked when the fingers touch down; `.unavailable` leaves the whole swipe to macOS.
    func dockSwipeMayStart() -> StripDockSwipeStart
    /// `positive` is the sign of macOS's progress, as macOS reports it for the axis.
    func dockSwipeBegan(positive: Bool, progress: Double, timestamp: Double) -> StripDockSwipeStart
    func dockSwipeChanged(_ progress: Double, timestamp: Double)
    func dockSwipeEnded(commit: Bool, progress: Double, velocity: Double, timestamp: Double)
}

/// One Dock swipe at a time: whether WinMuxX or macOS owns it, and when WinMuxX releases
/// it, whether it completes. Progress is macOS's travel since touchdown, signed by direction.
@MainActor
struct StripDockSwipeTracker {
    enum Verdict: Equatable {
        case pass
        /// Kept from the Dock until WinMuxX knows the swipe is its own.
        case hold
        case swallow
        /// macOS gets the swipe after all: post what was held, then this event.
        case replayHeldThenPass
        /// The Dock still sees the gesture end, with no motion to act on.
        case passWithoutMotion
    }
    enum Phase: Int64 { case began = 1, changed = 2, ended = 4, cancelled = 8 }
    private enum State: Equatable { case idle, passing, undecided, ignoring, claimed(sign: Double) }

    /// Below this, the sign of the travel is touchdown wobble rather than a direction.
    static let directionThreshold = 0.05
    /// On macOS 27 the Dock needs the real Ended to close its gesture state.
    let dockNeedsEnd: Bool
    private var state = State.idle
    private var progress = 0.0
    private var sampleTime = 0.0
    private(set) var velocity = 0.0
    private(set) var summary = StripDockSwipeSummary()

    init(dockNeedsEnd: Bool = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27) {
        self.dockNeedsEnd = dockNeedsEnd
    }

    /// WinMuxX owns the swipe, so the generic gesture events that come with it stay away from the Dock.
    var ownsGesture: Bool {
        switch state {
            case .claimed, .ignoring: true
            default: false
        }
    }

    /// Not yet known whose the swipe is: its generic gesture events wait with it.
    var isUndecided: Bool { state == .undecided }

    /// Past halfway unless flicked back, or a flick forward that has travelled a little.
    /// `velocity` is in progress per second toward the target; negative heads back.
    static func shouldCommit(progress: Double, velocity: Double) -> Bool {
        progress >= 0.5 ? velocity > -flickSpeed : progress >= 0.16 && velocity >= flickSpeed
    }
    /// A flick, in macOS's own release velocity (progress per second).
    static let flickSpeed = 1.5

    /// Ends a swipe WinMuxX owns without completing it, when its events stop arriving.
    mutating func abandon(_ receiver: some StripDockSwipeReceiver) {
        if case .claimed = state {
            receiver.dockSwipeEnded(commit: false, progress: progress, velocity: 0, timestamp: sampleTime)
        }
        state = .idle
    }

    mutating func receive(phase rawPhase: Int64, progress raw: Double, endVelocity: Double, timestamp: Double,
                          to receiver: some StripDockSwipeReceiver) -> Verdict {
        guard let phase = Phase(rawValue: rawPhase) else {
            switch state {
                case .idle, .passing: return .pass
                case .undecided: return .hold
                case .ignoring, .claimed: return .swallow
            }
        }
        switch phase {
            case .began:
                abandon(receiver)
                summary = StripDockSwipeSummary()
                switch receiver.dockSwipeMayStart() {
                    case .unavailable:
                        state = .passing
                        summary.outcome = "left to macOS"
                        return .pass
                    case .ignored:
                        state = .ignoring
                        summary.outcome = "ignored"
                        return .swallow
                    case .started:
                        state = .undecided
                        return .hold
                }
            case .changed:
                summary.samples += 1
                summary.maximumProgress = max(summary.maximumProgress, abs(raw))
                switch state {
                    case .idle, .passing: return .pass
                    case .ignoring: return .swallow
                    case .undecided:
                        guard abs(raw) >= Self.directionThreshold else { return .hold }
                        return start(sign: raw > 0 ? 1 : -1, progress: abs(raw), timestamp: timestamp, receiver)
                    case .claimed(let sign):
                        track(min(1, max(0, raw * sign)), timestamp: timestamp)
                        receiver.dockSwipeChanged(progress, timestamp: timestamp)
                        return .swallow
                }
            case .ended:
                summary.endVelocity = endVelocity
                defer { state = .idle }
                let close: Verdict = dockNeedsEnd ? .passWithoutMotion : .swallow
                switch state {
                    case .idle, .passing: return .pass
                    case .ignoring: return close
                    case .undecided:
                        // A flick can end before any sample travelled far enough to say which way.
                        guard endVelocity != 0 else { summary.outcome = "no direction"; return .replayHeldThenPass }
                        let verdict = start(sign: endVelocity > 0 ? 1 : -1, progress: 0, timestamp: timestamp, receiver)
                        guard verdict == .swallow else { return verdict }
                        if case .claimed = state { finish(commit: true, velocity: 0, timestamp: timestamp, receiver) }
                        return close
                    case .claimed(let sign):
                        // macOS measures the release itself, signed like its progress, and it
                        // already reads near zero when the fingers rested before lifting. Without
                        // it, a velocity from a sample long before the lift is not a flick.
                        let velocity = endVelocity != 0 ? endVelocity * sign
                            : timestamp - sampleTime < 0.08 ? velocity : 0
                        finish(commit: Self.shouldCommit(progress: progress, velocity: velocity),
                               velocity: velocity, timestamp: timestamp, receiver)
                        return close
                }
            case .cancelled:
                defer { state = .idle }
                switch state {
                    case .idle, .passing: return .pass
                    case .claimed:
                        finish(commit: false, velocity: 0, timestamp: timestamp, receiver)
                        return .swallow
                    case .undecided, .ignoring: return .swallow
                }
        }
    }

    private mutating func start(sign: Double, progress: Double, timestamp: Double,
                                _ receiver: some StripDockSwipeReceiver) -> Verdict {
        switch receiver.dockSwipeBegan(positive: sign > 0, progress: progress, timestamp: timestamp) {
            case .started:
                state = .claimed(sign: sign)
                self.progress = progress
                sampleTime = timestamp
                velocity = 0
                return .swallow
            case .ignored:
                state = .ignoring
                summary.outcome = "ignored"
                return .swallow
            case .unavailable:
                state = .passing
                summary.outcome = "left to macOS"
                return .replayHeldThenPass
        }
    }

    private mutating func track(_ next: Double, timestamp: Double) {
        let dt = timestamp - sampleTime
        if dt > 0.001 && dt <= 0.1 {
            let instant = (next - progress) / dt
            velocity = velocity == 0 ? instant : (velocity + instant) / 2
        } else if dt > 0.1 {
            velocity = 0
        }
        progress = next
        sampleTime = timestamp
    }

    private mutating func finish(commit: Bool, velocity: Double, timestamp: Double, _ receiver: some StripDockSwipeReceiver) {
        summary.finalProgress = progress
        summary.velocity = velocity
        summary.outcome = commit ? "completed" : "cancelled"
        receiver.dockSwipeEnded(commit: commit, progress: progress, velocity: velocity, timestamp: timestamp)
    }
}

/// The last swipe, for `winmuxx doctor`: macOS's progress scale and end velocity are
/// private, so these are what to compare when a swipe does not feel native.
struct StripDockSwipeSummary: Equatable {
    var samples = 0
    var maximumProgress = 0.0
    var finalProgress = 0.0
    var velocity = 0.0
    var endVelocity = 0.0
    var outcome = "none"
}



/// The receiver affects only the currently visible, ordinary native desktop.
@MainActor
private final class StripDockPanReceiver: StripDockSwipeReceiver {
    func dockSwipeMayStart() -> StripDockSwipeStart {
        guard config.scrolling.threeFingerSwipe, config.scrolling.gestureEnabled,
              TrayMenuModel.shared.isEnabled, !NativeScrollingPan.shared.isPanning,
              let monitor = sortedMonitors.first(where: { $0.rect.contains(mouseLocation) }),
              let desktop = nativeActiveDesktop(on: monitor), desktop.isVisible,
              desktop.scrollingMetrics.columns.count > 1 else { return .unavailable }
        return .started
    }
    func dockSwipeBegan(positive: Bool, progress: Double, timestamp: Double) -> StripDockSwipeStart {
        NativeScrollingPan.shared.beginDockSwipe(positive: positive, progress: progress) ? .started : .unavailable
    }
    func dockSwipeChanged(_ progress: Double, timestamp: Double) {
        NativeScrollingPan.shared.updateDockSwipe(progress)
    }
    func dockSwipeEnded(commit: Bool, progress: Double, velocity: Double, timestamp: Double) {
        // The viewport has already tracked the fingers; snap to the nearest
        // column on lift, regardless of whether macOS would switch Spaces.
        NativeScrollingPan.shared.endDockSwipe()
    }
}

@MainActor
final class StripDockSwipeSource {
    static let shared = StripDockSwipeSource()
    private var dockTap: (port: CFMachPort, source: CFRunLoopSource)?
    private var envelopeTap: (port: CFMachPort, source: CFRunLoopSource)?
    private var envelopeEnabled = false
    private var held: [CGEvent] = []
    private var tracker = StripDockSwipeTracker()
    private let receiver = StripDockPanReceiver()
    private var wakeObservers: [NSObjectProtocol] = []
    private(set) var status = "Disabled"

    func syncConfiguration() {
        stop()
        guard !isUnitTest, !serverArgs.isReadOnly, config.scrolling.threeFingerSwipe,
              config.scrolling.gestureEnabled else { return }
        guard stripTrackpadGesture("TrackpadThreeFingerHorizSwipeGesture") == 2 else {
            status = "Enable three-finger horizontal Space swipes in macOS Trackpad settings"
            return
        }
        guard let dock = makeTap(type: Self.dockControl), let envelope = makeTap(type: Self.gesture) else {
            status = "Event tap unavailable"
            return
        }
        dockTap = dock
        envelopeTap = envelope
        CGEvent.tapEnable(tap: envelope.port, enable: false)
        status = "Experimental three-finger horizontal strip pan"
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil,
                queue: .main) { _ in
                MainActor.assumeIsolated { StripDockSwipeSource.shared.revive() }
            })
        }
    }

    func stop() {
        tracker.abandon(receiver)
        if NativeScrollingPan.shared.isPanning { NativeScrollingPan.shared.cancel() }
        held.removeAll()
        for tap in [dockTap, envelopeTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap.port, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tap.source, .commonModes)
            CFMachPortInvalidate(tap.port)
        }
        dockTap = nil
        envelopeTap = nil
        envelopeEnabled = false
        wakeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        wakeObservers.removeAll()
        status = "Disabled"
    }

    private func revive() {
        guard let dockTap, let envelopeTap else { return }
        if !CFMachPortIsValid(dockTap.port) || !CFMachPortIsValid(envelopeTap.port) {
            syncConfiguration()
        } else if !CGEvent.tapIsEnabled(tap: dockTap.port) {
            CGEvent.tapEnable(tap: dockTap.port, enable: true)
        }
    }

    private func makeTap(type: Int64) -> (port: CFMachPort, source: CFRunLoopSource)? {
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(1) << CGEventMask(type),
            callback: stripDockSwipeTapCallback, userInfo: nil),
            let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return (port, source)
    }

    fileprivate func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tracker.abandon(receiver)
            NativeScrollingPan.shared.cancel()
            held.removeAll()
            if let dockTap { CGEvent.tapEnable(tap: dockTap.port, enable: true) }
            setEnvelope(false)
            return false
        }
        defer { setEnvelope(tracker.ownsGesture || tracker.isUndecided) }
        let subtype = event.getIntegerValueField(Self.field(Self.eventTypeField))
        if subtype == Self.gesture {
            if tracker.isUndecided {
                if let copy = event.copy() { held.append(copy) }
                return true
            }
            return tracker.ownsGesture
        }
        guard subtype == Self.dockControl,
              event.getIntegerValueField(Self.field(Self.hidType)) == Self.dockSwipe,
              event.getIntegerValueField(.eventSourceUnixProcessID) == 0,
              event.getIntegerValueField(Self.field(Self.swipeMotion)) == Self.motionHorizontal else { return false }
        let verdict = tracker.receive(
            phase: event.getIntegerValueField(Self.field(Self.phase)),
            progress: event.getDoubleValueField(Self.field(Self.progress)),
            endVelocity: event.getDoubleValueField(Self.field(Self.velocityX)),
            timestamp: Double(event.timestamp) / 1_000_000_000, to: receiver)
        switch verdict {
            case .pass:
                held.removeAll()
                return false
            case .hold:
                if let copy = event.copy() { held.append(copy) }
                return true
            case .swallow:
                held.removeAll()
                return true
            case .replayHeldThenPass:
                for earlier in held { earlier.tapPostEvent(proxy) }
                held.removeAll()
                return false
            case .passWithoutMotion:
                held.removeAll()
                for field in [Self.progress, Self.velocityX] {
                    event.setDoubleValueField(Self.field(field), value: 0)
                }
                return false
        }
    }

    private func setEnvelope(_ enabled: Bool) {
        guard enabled != envelopeEnabled, let envelopeTap else { return }
        envelopeEnabled = enabled
        CGEvent.tapEnable(tap: envelopeTap.port, enable: enabled)
    }

    // Same private fields used by WinMuxX and the existing NativeDockSwipe.
    private static let eventTypeField = 55, hidType = 110, swipeMotion = 123
    private static let progress = 124, velocityX = 129, phase = 132
    private static let gesture: Int64 = 29, dockControl: Int64 = 30, dockSwipe: Int64 = 23
    private static let motionHorizontal: Int64 = 1
    private static func field(_ raw: Int) -> CGEventField { CGEventField(rawValue: UInt32(raw))! }
}

private func stripDockSwipeTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                                       _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    nonisolated(unsafe) let mainThreadProxy = proxy
    nonisolated(unsafe) let mainThreadEvent = event
    let kept = MainActor.assumeIsolated {
        StripDockSwipeSource.shared.handle(mainThreadProxy, type, mainThreadEvent)
    }
    return kept ? nil : Unmanaged.passUnretained(event)
}

/// 2 means the macOS swipe is configured for three fingers.
func stripTrackpadGesture(_ key: String) -> Int {
    ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].compactMap {
        CFPreferencesAppSynchronize($0 as CFString)
        return CFPreferencesCopyAppValue(key as CFString, $0 as CFString) as? Int
    }.max() ?? 0
}

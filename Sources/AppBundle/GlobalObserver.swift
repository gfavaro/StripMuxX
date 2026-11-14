import AppKit
import Common
import HotKey

/// Keyboard and pointer events that feed tap and sequence bindings and the minimap's
/// hold modifiers. Window and Space changes come from `NativeSpacesObservation`.
enum GlobalObserver {
    @MainActor private static var isInitialized = false
    @MainActor private static var eventMonitorTokens: [Any] = []

    // NSEvent monitor callbacks arrive on the main thread. Running their bodies synchronously
    // instead of spawning a Task avoids an allocation + run-loop hop per input event — pointer
    // events fire at 60-120Hz, so the Task-per-event pattern adds constant latency and churn.
    private static func runOnMainActor(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }

    private static func onFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        runOnMainActor {
            noteTapBindingFlagsChanged(keyCode: keyCode, modifierFlags: modifierFlags)
            WorkspaceScrollingMinimap.shared.modifiersChanged(modifierFlags)
        }
    }

    @MainActor
    static func initObserver() {
        guard !isInitialized else { return }
        isInitialized = true
        // A click or scroll between a modifier's press and release means it was not a tap.
        let pointerActivityMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        ]
        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: pointerActivityMask) { _ in runOnMainActor { noteTapBindingKeyDown() } })
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: pointerActivityMask) { event in
            runOnMainActor { noteTapBindingKeyDown() }
            return event
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: onFlagsChanged))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            onFlagsChanged(event)
            return event
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in runOnMainActor { noteTapBindingKeyDown() } })
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            runOnMainActor { noteTapBindingKeyDown() }
            // Check if this key matches a recently-pressed prefix (sequence binding)
            if handleSequenceKeyDown(event: event) {
                return nil // consume the event
            }
            // If this is a sequence prefix key (e.g. Escape), arm the sequence detector
            if let prefix = Key(carbonKeyCode: UInt32(event.keyCode)),
               sequenceBindingsPrefixKeys.contains(prefix) {
                noteSequencePrefixKeyPressed(prefix)
            }
            if event.modifierFlags.contains(.control), event.keyCode == 34 {
                return nil // consume the event
            }
            return event
        })
    }

    @MainActor private static func retainEventMonitor(_ monitor: Any?) {
        guard let monitor else { return }
        eventMonitorTokens.append(monitor)
    }
}

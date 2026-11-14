import Common

/// Refreshes what follows an observation (the tray and desktop history) once per
/// burst of completed reads.
@MainActor
final class NativeObservationChrome {
    static let shared = NativeObservationChrome()
    private var task: Task<Void, Never>?
    private(set) var requests = 0
    private(set) var refreshes = 0

    func schedule() {
        requests += 1
        guard task == nil else { return }
        let owner = runtime
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard let self else { return }
            self.task = nil
            self.refreshes += 1
            owner.withValue {
                updateTrayText()
                owner.native.noteNativeActivity()
            }
        }
    }
}

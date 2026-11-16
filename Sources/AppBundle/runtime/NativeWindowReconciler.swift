import AppKit
import Common
import NativeSpaces

/// Read-only adoption into the existing layout tree. WindowServer supplies
/// membership, CG supplies process ownership, AX supplies window classification.
/// Failure/absence from AX is never a window-closure signal.
@MainActor
final class NativeWindowReconciler {
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private(set) var lastDurationMilliseconds: Double?
    private(set) var lastError: String?
    private(set) var pendingWindowCount = 0
    private(set) var writePreflight: (passed: Int, blocked: Int)?
    private(set) var timedOutAppCount = 0

    func invalidate() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    func reconcile(_ snapshot: NativeSpacesSnapshot) {
        invalidate()
        guard AXIsProcessTrusted(), !isUnitTest else { return }
        let version = generation
        let owner = runtime
        task = owner.task { [weak self, weak owner] in
            guard let self, let owner else { return }
            let started = ContinuousClock.now
            do {
                let eligible = Set(snapshot.windows.compactMap { membership in
                    owner.native.layouts.registrationWorkspace(for: membership.windowID) == nil ? nil : membership.windowID
                })
                let pids = await Task.detached { nativeWindowOwnerPIDs(eligible) }.value
                try Task.checkCancellation()
                guard self.generation == version else { return }
                Self.updateEligibility(snapshot, windows: MacWindow.allWindows, ownerPIDs: pids,
                    layouts: owner.native.layouts)
                for app in Array(MacApp.allAppsMap.values) where app.nsApp.isTerminated {
                    try Task.checkCancellation()
                    await app.destroy()
                }
                try await self.registerWindows(Dictionary(grouping: pids.keys, by: { pids[$0]! }), version: version, owner: owner)
                guard self.generation == version else { return }
                // Absence from AX, membership inventory or a failed bounds query
                // never proves closure. Individual closure comes from the native
                // close event; process death is independently confirmed here.
                for window in MacWindow.allWindows where window.macApp.nsApp.isTerminated {
                    window.garbageCollect()
                }
                self.pendingWindowCount = eligible.filter { MacWindow.allWindowsMap[$0] == nil }.count
                let identities = Self.writeIdentities(snapshot: snapshot, eligible: eligible, layouts: owner.native.layouts)
                let result = await Self.preflight(snapshot: snapshot, identities: identities)
                guard self.generation == version else { return }
                self.writePreflight = (result.passed.count, result.blocked)
                owner.native.observation?.watchManagedWindows(Set(MacWindow.allWindowsMap.keys))
                await owner.native.tiling.accept(snapshot, identities: identities.filter { result.passed.contains($0.windowID) })
                self.lastError = nil
            } catch is CancellationError { return }
            catch { if self.generation == version { self.lastError = String(describing: error) } }
            guard self.generation == version else { return }
            let duration = started.duration(to: .now).components
            self.lastDurationMilliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            self.task = nil
        }
    }

    /// Registers each app's eligible windows concurrently. An app that does not answer within its
    /// budget is counted, and the others carry on.
    private func registerWindows(_ groups: [Int32: [UInt32]], version: UInt64, owner: WinMuxRuntime) async throws {
        timedOutAppCount = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (pid, ids) in groups {
                group.addTask { @Sendable @MainActor in
                    let work = owner.throwingTask {
                        guard let running = NSRunningApplication(processIdentifier: pid),
                              running.activationPolicy == .regular, !running.isTerminated,
                              let app = try await MacApp.getOrRegister(running) else { return }
                        for id in ids.sorted() {
                            try Task.checkCancellation()
                            guard self.generation == version else { throw CancellationError() }
                            let window = try? await MacWindow.getOrRegister(windowId: id, macApp: app)
                            window?.nativeLayoutEligible = window != nil
                        }
                    }
                    // Match the existing app refresh's cooperative budget.
                    // An AX call already dispatched still has to answer or
                    // hit its 1s messaging timeout; other apps keep running.
                    let deadline = Task { @MainActor in
                        do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
                        work.cancel()
                    }
                    defer { deadline.cancel() }
                    try await withTaskCancellationHandler {
                        do { try await work.value }
                        catch is CancellationError {
                            try Task.checkCancellation()
                            if self.generation == version { self.timedOutAppCount += 1 }
                        }
                    } onCancel: { work.cancel() }
                }
            }
            try await group.waitForAll()
        }
    }

    /// The windows tiling may write: registered, on a desktop of a known Space, owned by a process
    /// that has not been replaced.
    private static func writeIdentities(snapshot: NativeSpacesSnapshot, eligible: Set<UInt32>,
                                        layouts: NativeSpaceLayouts) -> [NativeWindowWriteIdentity] {
        MacWindow.allWindows.compactMap { window -> NativeWindowWriteIdentity? in
            guard window.nativeLayoutEligible, eligible.contains(window.windowId), let launched = window.macApp.nsApp.processLaunchDate,
                  layouts.registrationWorkspace(for: window.windowId) === window.nodeWorkspace else { return nil }
            guard let display = layouts.registrationDisplay(for: window.windowId),
                  case .desktop(let spaceID, let uuid?) = snapshot.eligibility(windowID: window.windowId, on: display) else { return nil }
            return NativeWindowWriteIdentity(windowID: window.windowId, pid: window.macApp.pid,
                processLaunchDate: launched, displayIdentifier: display, spaceID: spaceID, spaceUUID: uuid)
        }
    }

    /// A local, read-only probe of which identities could be written to. Never populates the
    /// runtime's write authority: observation mode remains physically read-only.
    private static func preflight(snapshot: NativeSpacesSnapshot,
                                  identities: [NativeWindowWriteIdentity]) async -> (passed: [UInt32], blocked: Int) {
        let probe = Task.detached {
            let authority = NativeSpaceWriteAuthority()
            authority.replace(snapshot: snapshot, identities: identities)
            var passed: [UInt32] = []
            for identity in identities {
                if Task.isCancelled { break }
                if let permit = authority.permit(windowID: identity.windowID, pid: identity.pid,
                    processLaunchDate: identity.processLaunchDate), (try? permit.check()) != nil { passed.append(identity.windowID) }
            }
            return (passed: passed, blocked: identities.count - passed.count)
        }
        return await withTaskCancellationHandler { await probe.value } onCancel: { probe.cancel() }
    }

    static func updateEligibility(_ snapshot: NativeSpacesSnapshot, windows: [Window],
                                  ownerPIDs: [UInt32: Int32], layouts: NativeSpaceLayouts) {
        let queried = Set(snapshot.reconciliationSpaceIDs ?? snapshot.displays.map(\.activeSpaceID))
        for window in windows {
            let owners = snapshot.displays.filter {
                layouts.activeWorkspace(on: $0.identifier) === window.nodeWorkspace
            }
            guard !owners.isEmpty else { window.nativeLayoutEligible = false; continue }
            // Incoming-Space reads deliberately omit the unchanged displays'
            // memberships. Retain their presentation, but never fabricate fresh
            // write authority from that retained state.
            guard owners.contains(where: { queried.contains($0.activeSpaceID) }) else { continue }
            window.nativeLayoutEligible = ownerPIDs[window.windowId] == window.app.pid &&
                layouts.registrationWorkspace(for: window.windowId) === window.nodeWorkspace
        }
    }
}

private func nativeWindowOwnerPIDs(_ ids: Set<UInt32>) -> [UInt32: Int32] {
    guard let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var result: [UInt32: Int32] = [:]
    for row in rows {
        guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value, ids.contains(id),
              (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              pid > 0, pid != getpid() else { continue }
        result[id] = pid
    }
    return result
}

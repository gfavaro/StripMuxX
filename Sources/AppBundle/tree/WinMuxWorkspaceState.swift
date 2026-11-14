import AppKit

/// Which desktop a display shows, as last observed.
@MainActor
struct MonitorViewport {
    let id: MonitorViewportId
    var activeWorkspaceId: WorkspaceId?
}

@MainActor
struct WinMuxWorkspaceState {
    var workspaceById: [WorkspaceId: Workspace] = [:] {
        didSet { sortedWorkspacesCache = nil }
    }
    /// Workspace.all is read often and sorting by logical name segments isn't free. A
    /// workspace's name never changes, so the order only changes with the registry.
    private var sortedWorkspacesCache: [Workspace]? = nil
    var workspaceIdByName: [String: WorkspaceId] = [:]
    var monitorViewportsById: [MonitorViewportId: MonitorViewport] = [:]
    private var nextWorkspaceCounter = 1

    mutating func sortedWorkspaces() -> [Workspace] {
        if let cached = sortedWorkspacesCache { return cached }
        let sorted = workspaceById.values.sorted()
        sortedWorkspacesCache = sorted
        return sorted
    }

    mutating func nextWorkspaceId() -> WorkspaceId {
        while workspaceById[WorkspaceId("workspace-\(nextWorkspaceCounter)")] != nil {
            nextWorkspaceCounter += 1
        }
        defer { nextWorkspaceCounter += 1 }
        return WorkspaceId("workspace-\(nextWorkspaceCounter)")
    }

    func workspace(named name: String) -> Workspace? {
        workspaceIdByName[name].flatMap { workspaceById[$0] }
    }

    mutating func registerWorkspace(_ workspace: Workspace) {
        workspaceById[workspace.id] = workspace
        workspaceIdByName[workspace.name] = workspace.id
    }

    mutating func setActiveWorkspace(_ workspace: Workspace, on viewportId: MonitorViewportId) {
        runtime.events.record(.workspaceActivated, source: .model, generation: 0, workspaceID: workspace.id, viewport: viewportId)
        workspace.preferredMonitorPoint = viewportId.topLeftCorner
        monitorViewportsById[viewportId, default: MonitorViewport(id: viewportId)].activeWorkspaceId = workspace.id
    }
}

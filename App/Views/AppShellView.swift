import SwiftUI

@MainActor
private final class PanePool: ObservableObject {
    let shellHost = TerminalHost(frame: .zero)
    let agentHost = TerminalHost(frame: .zero)
    private var panes: [String: WorktreePane] = [:]
    @Published private(set) var activeIDs: Set<String> = []

    func getOrCreate(id: String, workingDirectory: String) {
        guard panes[id] == nil else { return }
        let pane = WorktreePane(workingDirectory: workingDirectory)
        panes[id] = pane
        shellHost.register(id: id, terminal: pane.shellView)
        agentHost.register(id: id, terminal: pane.agentView)
        activeIDs.insert(id)
    }

    func activate(id: String?) {
        shellHost.activate(id: id)
        agentHost.activate(id: id)
    }
}

struct AppShellView: View {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var pool = PanePool()
    @StateObject private var lazygit = LazygitWindow()
    @State private var selectedWorktreeID: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selectedWorktreeID: $selectedWorktreeID, activeTerminalIDs: pool.activeIDs)
        } detail: {
            WorktreeContentView(shellHost: pool.shellHost, agentHost: pool.agentHost)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            store.load()
        }
        .onChange(of: store.repos) { _, newRepos in
            guard selectedWorktreeID == nil,
                  let first = newRepos.first?.worktrees.first else { return }
            selectedWorktreeID = first.id
        }
        .onChange(of: selectedWorktreeID) { _, newID in
            pool.activate(id: newID)
            guard let id = newID,
                  let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
            else { return }
            pool.getOrCreate(id: id, workingDirectory: worktree.path)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLazygit)) { _ in
            guard let id = selectedWorktreeID,
                  let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
            else { return }
            lazygit.open(workingDirectory: worktree.path)
        }
    }
}

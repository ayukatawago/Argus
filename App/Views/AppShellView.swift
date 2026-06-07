import SwiftUI

@MainActor
private final class PanePool: ObservableObject {
    let host = TerminalHost(frame: .zero)
    private var panes: [String: WorktreePane] = [:]

    func getOrCreate(id: String, workingDirectory: String) {
        guard panes[id] == nil else { return }
        let pane = WorktreePane(workingDirectory: workingDirectory)
        panes[id] = pane
        host.register(id: id, terminal: pane.terminalView)
    }
}

struct AppShellView: View {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var pool = PanePool()
    @State private var selectedWorktreeID: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selectedWorktreeID: $selectedWorktreeID)
        } detail: {
            WorktreeContentView(host: pool.host)
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
            pool.host.activate(id: newID)
            guard let id = newID,
                  let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
            else { return }
            pool.getOrCreate(id: id, workingDirectory: worktree.path)
        }
    }
}

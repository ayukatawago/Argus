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
        try? WorktreeHookManager.install(worktreePath: workingDirectory)
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
    @StateObject private var agentBus = AgentStateBus()
    @State private var selectedWorktreeID: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                selectedWorktreeID: $selectedWorktreeID,
                activeTerminalIDs: pool.activeIDs,
                agentBus: agentBus
            )
        } detail: {
            terminalDetail
        }
        .onAppear {
            store.load()
            agentBus.start()
        }
        .onChange(of: store.repos) { _, newRepos in
            guard selectedWorktreeID == nil,
                let first = newRepos.first?.worktrees.first
            else { return }
            selectedWorktreeID = first.id
        }
        .onChange(of: selectedWorktreeID) { _, newID in
            pool.activate(id: newID)
            guard let id = newID,
                let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
            else { return }
            pool.getOrCreate(id: id, workingDirectory: worktree.path)
            agentBus.reset(for: id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLazygit)) { _ in
            guard let id = selectedWorktreeID,
                let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
            else { return }
            lazygit.open(workingDirectory: worktree.path)
        }
    }

    private var currentAgentState: AgentState {
        guard let id = selectedWorktreeID else { return .idle }
        return agentBus.state(for: id)
    }

    @ViewBuilder
    private var terminalDetail: some View {
        WorktreeContentView(shellHost: pool.shellHost, agentHost: pool.agentHost)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(terminalBorder)
            .animation(.easeInOut(duration: 0.35), value: currentAgentState)
    }

    @ViewBuilder
    private var terminalBorder: some View {
        if currentAgentState == .done {
            Rectangle()
                .strokeBorder(Color.green.opacity(0.5), lineWidth: 2)
        }
    }
}

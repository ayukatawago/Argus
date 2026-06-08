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

    func release(id: String) {
        guard panes[id] != nil else { return }
        panes.removeValue(forKey: id)
        shellHost.unregister(id: id)
        agentHost.unregister(id: id)
        activeIDs.remove(id)
    }
}

struct AppShellView: View {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var pool = PanePool()
    @StateObject private var lazygit = LazygitWindow()
    @StateObject private var agentBus = AgentStateBus()
    @State private var selectedWorktreeID: String?
    @AppStorage("lastSelectedWorktreeID") private var persistedWorktreeID: String = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                selectedWorktreeID: $selectedWorktreeID,
                activeTerminalIDs: pool.activeIDs,
                agentBus: agentBus,
                onRelease: { id in
                    if selectedWorktreeID == id { selectedWorktreeID = nil }
                    pool.release(id: id)
                    agentBus.reset(for: id)
                }
            )
        } detail: {
            terminalDetail
        }
        .onAppear {
            store.load()
            agentBus.start()
        }
        .onChange(of: store.repos) { _, newRepos in
            guard selectedWorktreeID == nil else { return }
            let all = newRepos.flatMap(\.worktrees)
            if !persistedWorktreeID.isEmpty, all.contains(where: { $0.id == persistedWorktreeID }) {
                selectedWorktreeID = persistedWorktreeID
            } else if let first = all.first {
                selectedWorktreeID = first.id
            }
        }
        .onChange(of: selectedWorktreeID) { _, newID in
            if let newID { persistedWorktreeID = newID }
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
        .onReceive(NotificationCenter.default.publisher(for: .focusShellPane)) { _ in
            pool.shellHost.focusActiveTerminal()
            dismissDoneIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAgentPane)) { _ in
            pool.agentHost.focusActiveTerminal()
            dismissDoneIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceInteracted)) { _ in
            dismissDoneIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectNextWorktree)) { _ in
            navigateWorktrees(forward: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectPreviousWorktree)) { _ in
            navigateWorktrees(forward: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshWorkspace)) { _ in
            Task { await store.refresh() }
        }
    }

    private func navigateWorktrees(forward: Bool) {
        let all = store.repos.flatMap(\.worktrees).filter {
            !store.hiddenWorktreeIDs.contains($0.id) && pool.activeIDs.contains($0.id)
        }
        guard !all.isEmpty else { return }
        guard let current = selectedWorktreeID,
              let idx = all.firstIndex(where: { $0.id == current })
        else {
            selectedWorktreeID = all.first?.id
            return
        }
        let next = forward ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        selectedWorktreeID = all[next].id
    }

    private var currentAgentState: AgentState {
        guard let id = selectedWorktreeID else { return .idle }
        return agentBus.state(for: id)
    }

    @ViewBuilder
    private var terminalDetail: some View {
        WorktreeContentView(shellHost: pool.shellHost, agentHost: pool.agentHost)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(terminalBackground)
            .overlay(terminalBorder)
    }

    @ViewBuilder
    private var terminalBackground: some View {
        switch currentAgentState {
        case .done:
            Color(nsColor: .systemGreen).opacity(0.05)

        case .waitingForApproval:
            Color(nsColor: .systemOrange).opacity(0.07)

        default:
            Color.clear
        }
    }

    @ViewBuilder
    private var terminalBorder: some View {
        switch currentAgentState {
        case .done:
            Rectangle()
                .strokeBorder(Color(nsColor: .systemGreen).opacity(0.5), lineWidth: 2)

        case .waitingForApproval:
            Rectangle()
                .strokeBorder(Color(nsColor: .systemOrange).opacity(0.7), lineWidth: 3)

        default:
            EmptyView()
        }
    }

    private func dismissDoneIfNeeded() {
        guard let id = selectedWorktreeID, agentBus.state(for: id) != .idle else { return }
        agentBus.reset(for: id)
    }
}

import GhosttyTerminal
import SwiftUI

struct WorktreeCard {
    let id: String
    let name: String
    let branch: String?
}

@MainActor
private final class PanePool: ObservableObject {
    let shellHost = TerminalHost(frame: .zero)
    let agentHost = TerminalHost(frame: .zero)
    private var panes: [String: WorktreePane] = [:]
    @Published private(set) var activeIDs: Set<String> = []
    @Published private(set) var canvasViews: [String: AppTerminalView] = [:]
    var agentBus: AgentStateBus?

    func getOrCreate(id: String, workingDirectory: String) {
        guard panes[id] == nil else { return }
        try? WorktreeHookManager.install(worktreePath: workingDirectory)
        let pane = WorktreePane(workingDirectory: workingDirectory)
        panes[id] = pane
        shellHost.register(id: id, terminal: pane.shellView)
        agentHost.register(id: id, terminal: pane.agentView)
        activeIDs.insert(id)
        if ArgusConfigStore.shared.config.agent == .codex {
            agentBus?.setAgentType(.codex, for: workingDirectory)
        }
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
        canvasViews.removeValue(forKey: id)
    }

    func openCanvas(worktrees: [(id: String, path: String)], fontSize: Int) {
        for (id, path) in worktrees where canvasViews[id] == nil {
            let session = WorktreePane.sessionName("a", path: path)
            let attachCmd =
                "tmux attach-session -t \(session)"
                + " \\; set -s extended-keys on"
                + " \\; set-option -t \(session) status off"
            let state = TerminalViewState(
                terminalConfiguration: TerminalConfiguration {
                    $0.withFontSize(Float(fontSize))
                    $0.withCursorStyleBlink(false)
                    $0.withCustom("command", attachCmd)
                }
            )
            state.configuration = TerminalSurfaceOptions(backend: .exec, workingDirectory: path)
            canvasViews[id] = WorktreePane.makeView(state: state, sessionName: session)
        }
    }

    func closeCanvas() {
        canvasViews.removeAll()
    }

    func reloadAgentPane(id: String, workingDirectory: String) {
        let session = WorktreePane.sessionName("a", path: workingDirectory)
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["tmux", "kill-session", "-t", session]
        try? task.run()
        release(id: id)
        getOrCreate(id: id, workingDirectory: workingDirectory)
        activate(id: id)
    }
}

struct AppShellView: View {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var pool = PanePool()
    @StateObject private var lazygit = LazygitWindow()
    @StateObject private var nvim = NvimWindow()
    @StateObject private var markdownPreview = MarkdownPreviewWindow()
    @StateObject private var agentBus = AgentStateBus()
    @StateObject private var diskMonitor = DiskMonitorStore()
    @StateObject private var diskScanner = DiskCleanupScanner()
    @StateObject private var diskStatusWindow = DiskStatusWindow()
    @Environment(\.openWindow) private var openWindow
    @State private var selectedWorktreeID: String?
    @State private var isCanvasMode = false
    @State private var lastFocusedHost: KeyPath<PanePool, TerminalHost> = \.shellHost
    @State private var detailSize: CGSize = .zero
    @AppStorage("lastSelectedWorktreeID") private var persistedWorktreeID: String = ""

    var body: some View {
        coreView
            .onReceive(NotificationCenter.default.publisher(for: .openLazygit)) { _ in
                guard let id = selectedWorktreeID,
                    let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
                else { return }
                lazygit.open(workingDirectory: worktree.path)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNvim)) { _ in
                guard let id = selectedWorktreeID,
                    let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
                else { return }
                nvim.open(workingDirectory: worktree.path)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMarkdownPreview)) { _ in
                guard let id = selectedWorktreeID,
                    let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
                else { return }
                markdownPreview.open(worktreePath: worktree.path)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                openWindow(id: "settings")
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadAgentPane)) { _ in
                guard let id = selectedWorktreeID,
                    let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
                else { return }
                pool.reloadAgentPane(id: id, workingDirectory: worktree.path)
                agentBus.reset(for: id)
                if ArgusConfigStore.shared.config.agent == .codex {
                    agentBus.setAgentType(.codex, for: worktree.path)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDiskStatus)) { _ in
                diskStatusWindow.open(store: diskMonitor, scanner: diskScanner)
            }
    }

    private var coreView: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if diskMonitor.isLow {
                    DiskLowBanner {
                        diskStatusWindow.open(store: diskMonitor, scanner: diskScanner)
                    }
                }
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
            }
        } detail: {
            terminalDetail
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { detailSize = geo.size }
                            .onChange(of: geo.size) { _, size in detailSize = size }
                    }
                )
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: toggleCanvas) {
                    Image(systemName: isCanvasMode ? "rectangle.split.3x1" : "square.grid.2x2")
                }
                .help(isCanvasMode ? "Exit canvas (⌘⇧C)" : "Canvas view (⌘⇧C)")
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
        .onAppear {
            pool.agentBus = agentBus
            store.load()
            agentBus.start()
            diskMonitor.start()
            diskScanner.start()
        }
        .onDisappear {
            diskMonitor.stop()
            diskScanner.stop()
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusShellPane)) { _ in
            lastFocusedHost = \.shellHost
            pool.shellHost.focusActiveTerminal()
            dismissDoneIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAgentPane)) { _ in
            lastFocusedHost = \.agentHost
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
            DispatchQueue.main.async { pool[keyPath: lastFocusedHost].focusActiveTerminal() }
            return
        }
        let next = forward ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        selectedWorktreeID = all[next].id
        DispatchQueue.main.async { pool[keyPath: lastFocusedHost].focusActiveTerminal() }
    }

    private var currentAgentState: AgentState {
        guard let id = selectedWorktreeID else { return .idle }
        return agentBus.state(for: id)
    }

    @ViewBuilder
    private var terminalDetail: some View {
        if isCanvasMode {
            CanvasView(
                worktrees: activeWorktrees,
                canvasViews: pool.canvasViews,
                agentBus: agentBus,
                onSelect: { id in
                    selectedWorktreeID = id
                    isCanvasMode = false
                    pool.closeCanvas()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WorktreeContentView(shellHost: pool.shellHost, agentHost: pool.agentHost, agentState: currentAgentState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(terminalBackground)
        }
    }

    private var activeWorktrees: [WorktreeCard] {
        store.repos.flatMap(\.worktrees)
            .filter { pool.activeIDs.contains($0.id) }
            .map { worktree in
                WorktreeCard(
                    id: worktree.id,
                    name: URL(fileURLWithPath: worktree.path).lastPathComponent,
                    branch: worktree.branch
                )
            }
    }

    private func toggleCanvas() {
        if isCanvasMode {
            pool.closeCanvas()
            isCanvasMode = false
        } else {
            let layout = CanvasLayout(count: activeWorktrees.count, available: detailSize)
            pool.openCanvas(
                worktrees: activeWorktrees.map { (id: $0.id, path: $0.id) },
                fontSize: layout.fontSize
            )
            isCanvasMode = true
        }
    }

    @ViewBuilder
    private var terminalBackground: some View {
        switch currentAgentState {
        case .done:
            Color.green.opacity(0.05)

        case .waitingForApproval:
            Color.orange.opacity(0.07)

        default:
            Color.clear
        }
    }

    private func dismissDoneIfNeeded() {
        guard let id = selectedWorktreeID else { return }
        let state = agentBus.state(for: id)
        guard state == .done || state == .waitingForApproval else { return }
        agentBus.reset(for: id)
    }
}

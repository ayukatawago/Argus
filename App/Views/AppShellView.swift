import AgentStateKit
import ArgusConfigKit
import ArgusSupport
import SwiftUI
import Workspaces

struct AppShellView: View {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var pool = PanePool()
    @StateObject private var popups = PopupTerminalManager()
    @StateObject private var nvim = NvimWindow()
    @StateObject private var markdownPreview = MarkdownPreviewWindow()
    @StateObject private var agentBus = AgentStateBus()
    @StateObject private var shellStateBus = ShellStateBus()
    @StateObject private var terminalTabs = TerminalTabsStore()
    // Not `private`: read by the `AppShellView+Toolbar` extension in another file.
    @StateObject var agentTabs = AgentTabsStore()
    @StateObject private var diskMonitor = DiskMonitorStore()
    @StateObject private var diskScanner = DiskCleanupScanner()
    @StateObject private var prMonitor = PRMonitorStore()
    @StateObject private var diskStatusWindow = DiskStatusWindow()
    @StateObject private var diffReview = DiffReviewWindow()
    @EnvironmentObject var configStore: ArgusConfigStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedWorktreeID: String?
    @State private var isCanvasMode = false
    @State var focusedRole: PaneRole = .shell
    @State private var detailSize: CGSize = .zero
    @AppStorage("lastSelectedWorktreeID") private var persistedWorktreeID: String = ""

    var body: some View {
        coreView
            .onReceive(NotificationCenter.default.publisher(for: .openPopupTerminal)) { notification in
                guard let shortcutID = notification.object as? String,
                    let shortcut = configStore.config.popupShortcuts.first(where: { $0.id == shortcutID }),
                    let id = selectedWorktreeID,
                    let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
                else { return }
                popups.open(shortcut, workingDirectory: worktree.path)
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
                let tabs = agentTabs.tabs(for: id)
                let roles = PaneLayoutResolver.requiredRoles(tabs: tabs)
                pool.reloadAgentPanes(id: id, workingDirectory: worktree.path, roles: roles)
                for agent in tabs.open {
                    agentBus.reset(for: worktree.path, agent: agent.agentType)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDiskStatus)) { _ in
                diskStatusWindow.open(store: diskMonitor, scanner: diskScanner)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDiffReview)) { _ in
                guard let id = selectedWorktreeID,
                    let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
                else { return }
                diffReview.open(worktreePath: worktree.path, agent: configStore.config.agent)
            }
            .onReceiveTabBindings(
                focusedRole: $focusedRole, terminalTabs: terminalTabs, agentTabs: agentTabs, pool: pool
            )
            .onReceive(NotificationCenter.default.publisher(for: .openDiffReviewForPath)) { notification in
                // CLI-originated (`argus diff`) request — the path is used as-is, independent of
                // whether it's a workspace `store` already tracks in the sidebar.
                guard let info = notification.userInfo, let workspace = info["workspace"] as? String else {
                    return
                }
                let base = info["base"] as? String ?? ""
                let head = info["head"] as? String ?? "HEAD"
                diffReview.open(worktreePath: workspace, base: base, head: head, agent: configStore.config.agent)
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
                    shellStateBus: shellStateBus,
                    prMonitor: prMonitor,
                    onRelease: { id in
                        if selectedWorktreeID == id { selectedWorktreeID = nil }
                        pool.release(id: id)
                        agentBus.reset(for: id)
                        agentTabs.release(id: id)
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
            ToolbarItem(placement: .automatic) {
                Button {
                    NotificationCenter.default.post(name: .openDiffReview, object: nil)
                } label: {
                    Image(systemName: "square.split.2x1")
                }
                .help("Review diff")
                .disabled(selectedWorktreeID == nil)
            }
            ToolbarItem(placement: .automatic) {
                agentPaneModeToggle
            }
            ToolbarItem(placement: .automatic) {
                layoutPicker
            }
        }
        .onAppear {
            store.load()
            agentTabs.attach(pool: pool, agentBus: agentBus)
            agentBus.start()
            shellStateBus.updateActivePaths(pool.activeIDs)
            shellStateBus.start()
            terminalTabs.start()
            diskMonitor.start()
            diskScanner.start()
            prMonitor.start()
            // Lets AppDelegate know it's safe to deliver a CLI-originated `argus://diff` request
            // instead of buffering it — see .openDiffReviewForPath above. A direct call (not a
            // NotificationCenter round trip) since ordering against AppDelegate's own setup isn't
            // guaranteed otherwise.
            AppDelegate.current?.markAppShellReady()
        }
        .onDisappear {
            shellStateBus.stop()
            terminalTabs.stop()
            diskMonitor.stop()
            diskScanner.stop()
            prMonitor.stop()
        }
        .onChange(of: pool.activeIDs) { _, ids in
            shellStateBus.updateActivePaths(ids)
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
            else {
                terminalTabs.setWorktree(path: nil)
                agentTabs.setWorktree(id: nil, path: nil, defaultAgent: configStore.config.agent)
                return
            }
            // Seed (or find) this worktree's open agent tabs before registering roles — the
            // required-role set comes from whatever tabs it ends up with.
            agentTabs.setWorktree(id: id, path: worktree.path, defaultAgent: configStore.config.agent)
            pool.getOrCreate(
                id: id, workingDirectory: worktree.path,
                roles: PaneLayoutResolver.requiredRoles(tabs: agentTabs.tabs(for: id)))
            terminalTabs.setWorktree(path: worktree.path)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPaneLeft)) { _ in
            stepFocus(direction: -1)
            dismissAttentionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPaneRight)) { _ in
            stepFocus(direction: +1)
            dismissAttentionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceInteracted)) { _ in
            dismissAttentionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectNextWorktree)) { _ in
            navigateWorktrees(forward: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectPreviousWorktree)) { _ in
            navigateWorktrees(forward: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshWorkspace)) { _ in
            store.requestRefresh()
        }
        .onChange(of: agentTabs.mode) { _, _ in clampFocusedRole() }
        .onChange(of: agentTabs.byWorktree) { _, _ in clampFocusedRole() }
    }

    // MARK: - Terminal detail

    private var currentWorktreeState: WorktreeAgentState {
        guard let id = selectedWorktreeID else { return .idle }
        return agentBus.worktreeState(for: id)
    }

    @ViewBuilder
    private var terminalDetail: some View {
        let config = configStore.config
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
        } else if let worktreePath = agentTabs.worktreePath {
            WorktreeContentView(
                layout: config.layout,
                shellHost: pool.shellHost,
                claudeHost: pool.claudeHost,
                codexHost: pool.codexHost,
                tabsStore: terminalTabs,
                agentTabs: agentTabs,
                agentBus: agentBus,
                worktreePath: worktreePath,
                onShellActivated: { focusedRole = .shell },
                onAgentActivated: { role in
                    focusedRole = role
                    Task { @MainActor in pool.host(for: role).focusActiveTerminal() }
                }
            )
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
            let worktrees = activeWorktrees.map {
                CanvasWorktree(id: $0.id, path: $0.id, role: agentTabs.tabs(for: $0.id).active.paneRole)
            }
            pool.openCanvas(worktrees: worktrees, fontSize: layout.fontSize)
            isCanvasMode = true
        }
    }

    @ViewBuilder
    private var terminalBackground: some View {
        switch currentWorktreeState.state {
        case .done:
            Color.green.opacity(0.05)

        case .waitingForApproval:
            Color.orange.opacity(0.07)

        default:
            Color.clear
        }
    }

}

extension AppShellView {
    fileprivate func dismissAttentionIfNeeded() {
        guard let id = selectedWorktreeID else { return }
        agentBus.dismissAttentionStates(for: id)
    }

    // MARK: - Directional focus

    fileprivate func stepFocus(direction: Int) {
        let ordered = PaneLayoutResolver.orderedRoles(
            layout: configStore.config.layout, tabs: agentTabs.tabs, mode: agentTabs.mode)
        guard !ordered.isEmpty else { return }
        let currentIndex = ordered.firstIndex(of: focusedRole) ?? 0
        let newIndex = max(0, min(ordered.count - 1, currentIndex + direction))
        focusedRole = ordered[newIndex]
        pool.host(for: focusedRole).focusActiveTerminal()
    }

    // MARK: - Worktree navigation

    fileprivate func navigateWorktrees(forward: Bool) {
        let eligibleIDs = store.repos.flatMap(\.worktrees)
            .filter { !store.hiddenWorktreeIDs.contains($0.id) && pool.activeIDs.contains($0.id) }
            .map(\.id)
        guard let next = WorktreeNavigator.next(from: selectedWorktreeID, in: eligibleIDs, forward: forward) else {
            return
        }
        selectedWorktreeID = next
        DispatchQueue.main.async { self.pool.host(for: self.focusedRole).focusActiveTerminal() }
    }
}

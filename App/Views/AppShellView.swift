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
    @StateObject private var agentDisplayWatcher = AgentPaneDisplayWatcher()
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
    // Not `private`: read by the `AppShellView+Toolbar` extension in another file, same reasoning
    // as `agentTabs` above.
    @EnvironmentObject var codexUsageStore: CodexUsageStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedWorktreeID: String?
    @State private var hasRestoredOpenWorktrees = false
    @State var isCodexUsagePopoverPresented = false
    @State var focusedRole: PaneRole = .shell
    @State private var isPaletteOpen = false
    @AppStorage("lastSelectedWorktreeID") private var persistedWorktreeID: String = ""

    /// `coreView` plus the HUD/palette overlays, split out of `body` to keep its modifier chain
    /// within what the type checker can solve.
    private var overlaidCoreView: some View {
        coreView
            .overlay(alignment: .bottom) { LeaderHUDView() }
            .overlay {
                if isPaletteOpen {
                    CommandPaletteView(
                        items: paletteItems(),
                        onSelect: selectPaletteItem,
                        onClose: closePalette
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
                if isPaletteOpen { closePalette() } else { isPaletteOpen = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jumpToAttention)) { _ in
                jumpToAttention()
            }
    }

    var body: some View {
        overlaidCoreView
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
                Task {
                    await pool.reloadAgentPanes(id: id, workingDirectory: worktree.path, roles: roles)
                    // reloadAgentPanes rebuilds every role's terminal view (including the shell's,
                    // to pick up the freshly re-registered pane), which leaves nothing as first
                    // responder — restore focus to whichever pane the user was last in rather than
                    // leaving the keyboard focus nowhere.
                    pool.host(for: focusedRole).focusActiveTerminal()
                }
                for agent in tabs.open {
                    agentBus.reset(for: worktree.path, agent: agent.agentType)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDiskStatus)) { _ in
                diskStatusWindow.open(store: diskMonitor, scanner: diskScanner)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCodexUsage)) { _ in
                isCodexUsagePopoverPresented.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDiffReview)) { _ in
                guard let id = selectedWorktreeID,
                    let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
                else { return }
                diffReview.open(worktreePath: worktree.path, agent: agent(forWorktreePath: worktree.path))
            }
            .onReceiveTabBindings(
                focusedRole: $focusedRole, terminalTabs: terminalTabs, agentTabs: agentTabs, pool: pool
            )
            .onReceiveTmuxPaneBindings(focusedRole: $focusedRole, worktreePath: agentTabs.worktreePath)
            .onReceiveFocusSync(focusedRole: $focusedRole, pool: pool)
            .onReceive(NotificationCenter.default.publisher(for: .openDiffReviewForPath)) { notification in
                // CLI-originated (`argus diff`) request — the path is used as-is, independent of
                // whether it's a workspace `store` already tracks in the sidebar.
                guard let info = notification.userInfo, let workspace = info["workspace"] as? String else {
                    return
                }
                let base = info["base"] as? String ?? ""
                let head = info["head"] as? String ?? "HEAD"
                diffReview.open(
                    worktreePath: workspace, base: base, head: head,
                    agent: agent(forWorktreePath: workspace))
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
        }
        .toolbar {
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
                codexUsageChip
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
            codexUsageStore.start()
            // Lets AppDelegate know it's safe to deliver a CLI-originated `argus://diff` request
            // instead of buffering it — see .openDiffReviewForPath above. A direct call (not a
            // NotificationCenter round trip) since ordering against AppDelegate's own setup isn't
            // guaranteed otherwise.
            AppDelegate.current?.markAppShellReady()
        }
        .onDisappear {
            agentBus.stop()
            shellStateBus.stop()
            terminalTabs.stop()
            diskMonitor.stop()
            diskScanner.stop()
            prMonitor.stop()
            codexUsageStore.stop()
        }
        .withAgentDisplayWatcher(agentDisplayWatcher, agentBus: agentBus, repos: store.repos)
        .onChange(of: pool.activeIDs) { _, ids in
            shellStateBus.updateActivePaths(ids)
            store.setOpenWorktreeIDs(ids)
        }
        .onChange(of: store.repos) { _, newRepos in
            let all = newRepos.flatMap(\.worktrees)
            if selectedWorktreeID == nil {
                if !persistedWorktreeID.isEmpty, all.contains(where: { $0.id == persistedWorktreeID }) {
                    selectedWorktreeID = persistedWorktreeID
                } else if let first = all.first {
                    selectedWorktreeID = first.id
                }
            }
            restoreOpenWorktreesIfNeeded(all: all)
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
            agentTabs.setWorktree(id: id, path: worktree.path, defaultAgent: agent(forWorktreePath: worktree.path))
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

    /// The agent to seed/use for the worktree at `path`: its project's override if the sidebar has
    /// one configured, otherwise the global default.
    fileprivate func agent(forWorktreePath path: String) -> AgentSelection {
        configStore.config.agent(forProjectPath: store.repoMainPath(forWorktreePath: path))
    }
}

extension AppShellView {
    // MARK: - Terminal detail

    fileprivate var currentWorktreeState: WorktreeAgentState {
        guard let id = selectedWorktreeID else { return .idle }
        return agentBus.worktreeState(for: id)
    }

    @ViewBuilder
    fileprivate var terminalDetail: some View {
        let config = configStore.config
        if let worktreePath = agentTabs.worktreePath {
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
        } else {
            WelcomeView(store: store)
        }
    }

    /// Reattaches every worktree that had a live pane open when the app last quit, so
    /// worktree-cycling shows them again immediately instead of only the last selection. Runs
    /// once per launch, the first time the scan produces a non-empty worktree list; the selected
    /// worktree (already handled above) is skipped here to avoid double-registering its roles.
    fileprivate func restoreOpenWorktreesIfNeeded(all: [GitWorktree]) {
        guard !hasRestoredOpenWorktrees, !all.isEmpty else { return }
        hasRestoredOpenWorktrees = true
        for worktree in all
        where worktree.id != selectedWorktreeID
            && store.openWorktreeIDs.contains(worktree.id)
            && !store.hiddenWorktreeIDs.contains(worktree.id)
        {
            agentTabs.seed(id: worktree.id, defaultAgent: agent(forWorktreePath: worktree.path))
            pool.getOrCreate(
                id: worktree.id, workingDirectory: worktree.path,
                roles: PaneLayoutResolver.requiredRoles(tabs: agentTabs.tabs(for: worktree.id)))
        }
    }

    fileprivate var terminalBackground: some View {
        currentWorktreeState.state.detailTint
    }

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

    /// Selects the next worktree whose agent is blocked on approval (first) or done awaiting a
    /// reply — the "what needs me now" jump.
    fileprivate func jumpToAttention() {
        let ordered = store.repos.flatMap(\.worktrees)
            .filter { !store.hiddenWorktreeIDs.contains($0.id) }
            .map(\.id)
        let next = WorktreeNavigator.nextAttention(from: selectedWorktreeID, in: ordered) { id in
            let state = agentBus.worktreeState(for: id).state
            return state == .waitingForApproval || state == .done ? state.displayPriority : nil
        }
        guard let next else { return }
        selectedWorktreeID = next
        DispatchQueue.main.async { self.pool.host(for: self.focusedRole).focusActiveTerminal() }
    }

    // MARK: - Command palette

    fileprivate func paletteItems() -> [PaletteItem] {
        PaletteItem.items(
            repos: store.repos, hidden: store.hiddenWorktreeIDs, config: configStore.config,
            agentState: { agentBus.worktreeState(for: $0) })
    }

    fileprivate func closePalette() {
        isPaletteOpen = false
        DispatchQueue.main.async { self.pool.host(for: self.focusedRole).focusActiveTerminal() }
    }

    fileprivate func selectPaletteItem(_ item: PaletteItem) {
        closePalette()
        if case .worktree(let id) = item.kind {
            selectedWorktreeID = id
        } else {
            DispatchQueue.main.async { item.postNotification() }
        }
    }
}

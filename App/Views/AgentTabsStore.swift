import AgentStateKit
import ArgusConfigKit
import Foundation

/// Per-worktree agent tab state and the app-global full/side-by-side display mode. Unlike
/// `TerminalTabsStore`, this is *not* a mirror over tmux — tmux has no notion of "which agent tabs
/// are open"; this store is the source of truth, and `PanePool` role registration is its
/// projection. Nothing here is persisted except `mode`: every launch starts each worktree with
/// only its default agent's tab open (seeded from `config.agent` at the moment a worktree is
/// first selected).
@MainActor
final class AgentTabsStore: ObservableObject {
    @Published private(set) var byWorktree: [String: AgentTabs] = [:]
    @Published private(set) var mode: AgentPaneMode = ArgusConfigStore.shared.config.agentPaneMode
    // Published (not just stored) so switching to an already-seeded worktree — which leaves
    // `byWorktree` untouched — still republishes; views key their agent-state lookups on this path.
    @Published private(set) var worktreeID: String?
    @Published private(set) var worktreePath: String?
    private weak var pool: PanePool?
    private weak var agentBus: AgentStateBus?

    /// `PanePool` and `AgentStateBus` are both `AppShellView` `@StateObject`s constructed
    /// independently of this store; wired together once, in `onAppear`.
    func attach(pool: PanePool, agentBus: AgentStateBus) {
        self.pool = pool
        self.agentBus = agentBus
    }

    /// The selected worktree's tabs, or a claude-only default when nothing is selected yet.
    var tabs: AgentTabs {
        guard let worktreeID else { return AgentTabs(defaultAgent: .claude) }
        return tabs(for: worktreeID)
    }

    func tabs(for id: String) -> AgentTabs {
        byWorktree[id] ?? AgentTabs(defaultAgent: .claude)
    }

    /// Switches to a different worktree (or none), seeding its tab set from `defaultAgent` the
    /// first time it's seen. An already-seeded worktree keeps whatever tabs it has — switching
    /// `config.agent` in Settings has no retroactive effect on worktrees already open.
    func setWorktree(id: String?, path: String?, defaultAgent: AgentSelection) {
        worktreeID = id
        worktreePath = path
        guard let id, byWorktree[id] == nil else { return }
        byWorktree[id] = AgentTabs(defaultAgent: defaultAgent)
    }

    /// Forgets a released worktree's open tabs — release means "forget", so reselecting it later
    /// re-seeds from the current default agent rather than silently respawning whatever was open.
    func release(id: String) {
        byWorktree.removeValue(forKey: id)
    }

    // MARK: - Actions

    @discardableResult
    func select(_ agent: AgentSelection) -> Bool {
        guard let id = worktreeID else { return false }
        var current = tabs(for: id)
        guard current.activate(agent) else { return false }
        byWorktree[id] = current
        return true
    }

    @discardableResult
    func selectRelative(_ delta: Int) -> Bool {
        guard let id = worktreeID else { return false }
        var current = tabs(for: id)
        guard current.activateRelative(delta) else { return false }
        byWorktree[id] = current
        return true
    }

    @discardableResult
    func openTab(_ agent: AgentSelection) -> Bool {
        guard let id = worktreeID, let path = worktreePath else { return false }
        var current = tabs(for: id)
        let opened = current.open(agent)
        byWorktree[id] = current
        if opened { pool?.openRole(id: id, workingDirectory: path, role: agent.paneRole) }
        return opened
    }

    /// Opens whichever agent doesn't have a tab yet — the `+` chip / leader-`t` action on the
    /// agent pane. No-op when both tabs are already open.
    @discardableResult
    func openClosedTab() -> Bool {
        guard let closed = tabs.closed else { return false }
        return openTab(closed)
    }

    /// Closes `agent`'s tab: kills its tmux session and unregisters its role. Refused (a no-op
    /// `Task`) when `agent` is the last open tab.
    @discardableResult
    func closeTab(_ agent: AgentSelection) -> Task<Void, Never> {
        guard let id = worktreeID, let path = worktreePath else { return Task {} }
        var current = tabs(for: id)
        guard current.close(agent) != nil else { return Task {} }
        byWorktree[id] = current
        agentBus?.reset(for: path, agent: agent.agentType)
        return Task { [pool] in
            await pool?.closeRole(id: id, workingDirectory: path, role: agent.paneRole)
        }
    }

    func setMode(_ mode: AgentPaneMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        ArgusConfigStore.shared.config.agentPaneMode = mode
        ArgusConfigStore.shared.save()
    }

    func toggleMode() {
        setMode(mode.toggled)
    }
}

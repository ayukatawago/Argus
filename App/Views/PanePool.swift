import AgentStateKit
import ArgusConfigKit
import ArgusSupport
import GhosttyTerminal
import SwiftUI

struct WorktreeCard {
    let id: String
    let name: String
    let branch: String?
}

/// One worktree's canvas attachment target — the session `PanePool.openCanvas` attaches to.
struct CanvasWorktree {
    let id: String
    let path: String
    let role: PaneRole
}

@MainActor
final class PanePool: ObservableObject {
    let shellHost = TerminalHost(frame: .zero)
    let claudeHost = TerminalHost(frame: .zero)
    let codexHost = TerminalHost(frame: .zero)
    private var panes: [String: WorktreePane] = [:]
    @Published private(set) var activeIDs: Set<String> = []
    @Published private(set) var canvasViews: [String: AppTerminalView] = [:]

    func host(for role: PaneRole) -> TerminalHost {
        switch role {
        case .shell: shellHost
        case .claude: claudeHost
        case .codex: codexHost
        }
    }

    /// Registers `roles` for `id`, building the worktree's pane (and its shell tmux session) on
    /// first use. `roles` is the caller's required-role set — see `PaneLayoutResolver.requiredRoles`
    /// and `AgentTabsStore` — so `PanePool` itself has no notion of layout or open agent tabs.
    func getOrCreate(id: String, workingDirectory: String, roles: [PaneRole]) {
        if panes[id] == nil {
            try? WorktreeHookManager.install(worktreePath: workingDirectory)
            let pane = WorktreePane(workingDirectory: workingDirectory)
            panes[id] = pane
            activeIDs.insert(id)
        }
        guard let pane = panes[id] else { return }
        for role in roles {
            host(for: role).register(id: id, terminal: pane.view(for: role))
        }
    }

    /// Registers a single additional role for an already-created worktree — the agent-tab
    /// analogue of opening a new tmux window. Idempotent.
    func openRole(id: String, workingDirectory: String, role: PaneRole) {
        getOrCreate(id: id, workingDirectory: workingDirectory, roles: [role])
    }

    func activate(id: String?) {
        shellHost.activate(id: id)
        claudeHost.activate(id: id)
        codexHost.activate(id: id)
    }

    func release(id: String) {
        guard panes[id] != nil else { return }
        panes.removeValue(forKey: id)
        shellHost.unregister(id: id)
        claudeHost.unregister(id: id)
        codexHost.unregister(id: id)
        activeIDs.remove(id)
        canvasViews.removeValue(forKey: id)
    }

    /// The agent-tab analogue of tmux `kill-window`: unmounts the surface, drops the pane's
    /// cached view for `role` so a later reopen builds a fresh one, then kills its tmux session so
    /// the next open starts a fresh agent rather than re-attaching to the old one. `role` must not
    /// be `.shell` — the shell pane is never closed this way.
    func closeRole(id: String, workingDirectory: String, role: PaneRole) async {
        guard role != .shell else { return }
        host(for: role).unregister(id: id)
        panes[id]?.discardView(for: role)
        canvasViews.removeValue(forKey: id)
        let session = WorktreePane.sessionName(for: role, path: workingDirectory)
        _ = await ProcessRunner.run(WorktreePane.tmuxExecutable, ["kill-session", "-t", session])
    }

    func openCanvas(worktrees: [CanvasWorktree], fontSize: Int) {
        for worktree in worktrees where canvasViews[worktree.id] == nil {
            let id = worktree.id
            let path = worktree.path
            let session = WorktreePane.sessionName(for: worktree.role, path: path)
            let tmux = WorktreePane.tmuxExecutable
            let attachCmd =
                "\(tmux) attach-session -t \(session)"
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

    /// Kills every currently-open agent role's tmux session, then rebuilds the worktree's pane
    /// with `roles` registered again. The shell session is untouched. Answers "reload with both
    /// tabs open" uniformly: whatever is open is killed and comes back — the open/active tab
    /// state itself lives in `AgentTabsStore`, which `release`/`getOrCreate` never touch.
    func reloadAgentPanes(id: String, workingDirectory: String, roles: [PaneRole]) async {
        for role in roles where role != .shell {
            let session = WorktreePane.sessionName(for: role, path: workingDirectory)
            _ = await ProcessRunner.run(WorktreePane.tmuxExecutable, ["kill-session", "-t", session])
        }
        release(id: id)
        getOrCreate(id: id, workingDirectory: workingDirectory, roles: roles)
        activate(id: id)
    }
}

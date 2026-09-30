import AgentStateKit
import ArgusConfigKit
import ArgusSupport
import SwiftUI

@MainActor
final class PanePool: ObservableObject {
    let shellHost = TerminalHost(frame: .zero)
    let claudeHost = TerminalHost(frame: .zero)
    let codexHost = TerminalHost(frame: .zero)
    private var panes: [String: WorktreePane] = [:]
    @Published private(set) var activeIDs: Set<String> = []

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
    }

    /// The agent-tab analogue of tmux `kill-window`: kills the role's tmux session, then unmounts
    /// the surface and drops the pane's cached view so a later reopen builds a fresh one against a
    /// fresh session rather than re-attaching to the old one. `role` must not be `.shell` — the
    /// shell pane is never closed this way.
    ///
    /// Killing the session before releasing the view (not after) matters: releasing the view's
    /// last strong reference synchronously tears down its native surface on the main thread, which
    /// blocks joining that surface's IO threads. If the tmux client is still alive in that surface's
    /// pty at that moment, that join can hang indefinitely (observed live as an 80s+ app freeze) —
    /// killing the session first lets the pty's child process exit and its IO threads unblock
    /// before teardown ever has to wait on them.
    func closeRole(id: String, workingDirectory: String, role: PaneRole) async {
        guard role != .shell else { return }
        let session = WorktreePane.sessionName(for: role, path: workingDirectory)
        _ = await ProcessRunner.run(WorktreePane.tmuxExecutable, ["kill-session", "-t", session])
        host(for: role).unregister(id: id)
        panes[id]?.discardView(for: role)
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

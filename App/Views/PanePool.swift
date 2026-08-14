import AgentStateKit
import ArgusConfigKit
import GhosttyTerminal
import SwiftUI

struct WorktreeCard {
    let id: String
    let name: String
    let branch: String?
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

    /// The roles that must be registered for a given layout + agent selection.
    static func requiredRoles(layout: WindowLayout, agent: AgentSelection) -> [PaneRole] {
        switch layout {
        case .terminalAgent:
            return [.shell, agent == .codex ? .codex : .claude]

        case .agentsOverTerminal, .terminalClaudeCodex:
            return [.shell, .claude, .codex]
        }
    }

    /// The primary agent role (determines which session canvas attaches to and which
    /// session reload targets).
    static func primaryAgentRole(layout: WindowLayout, agent: AgentSelection) -> PaneRole {
        switch layout {
        case .terminalAgent:
            return agent == .codex ? .codex : .claude

        case .agentsOverTerminal, .terminalClaudeCodex:
            return .claude
        }
    }

    /// Left-to-right (then top-to-bottom) pane order used for directional focus.
    static func orderedRoles(layout: WindowLayout, agent: AgentSelection) -> [PaneRole] {
        switch layout {
        case .terminalAgent:
            return [.shell, agent == .codex ? .codex : .claude]

        case .agentsOverTerminal:
            // Top-left Codex, top-right Claude, bottom Shell
            return [.codex, .claude, .shell]

        case .terminalClaudeCodex:
            return [.shell, .claude, .codex]
        }
    }

    func getOrCreate(id: String, workingDirectory: String) {
        let config = ArgusConfigStore.shared.config
        let roles = Self.requiredRoles(layout: config.layout, agent: config.agent)
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

    /// Register any newly-required roles for the selected worktree after a layout change.
    func applyLayout(id: String, workingDirectory: String) {
        getOrCreate(id: id, workingDirectory: workingDirectory)
        activate(id: id)
    }

    func openCanvas(worktrees: [(id: String, path: String)], fontSize: Int) {
        let config = ArgusConfigStore.shared.config
        for (id, path) in worktrees where canvasViews[id] == nil {
            let primaryRole = Self.primaryAgentRole(layout: config.layout, agent: config.agent)
            let session = WorktreePane.sessionName(primaryRole == .codex ? "x" : "a", path: path)
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

    func reloadAgentPane(id: String, workingDirectory: String) {
        let config = ArgusConfigStore.shared.config
        let primaryRole = Self.primaryAgentRole(layout: config.layout, agent: config.agent)
        var rolesToReload: Set<PaneRole> = [primaryRole]
        if Self.requiredRoles(layout: config.layout, agent: config.agent).contains(.codex) {
            rolesToReload.insert(.codex)
        }
        for role in rolesToReload {
            let typeChar = role == .codex ? "x" : "a"
            let session = WorktreePane.sessionName(typeChar, path: workingDirectory)
            let task = Process()
            task.launchPath = WorktreePane.tmuxExecutable
            task.arguments = ["kill-session", "-t", session]
            try? task.run()
        }
        release(id: id)
        getOrCreate(id: id, workingDirectory: workingDirectory)
        activate(id: id)
    }
}

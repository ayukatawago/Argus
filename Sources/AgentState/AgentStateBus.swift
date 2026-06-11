import Foundation

/// Aggregates agent state events from HookIPC and publishes per-worktree state.
/// Key is the worktree path, which matches GitWorktree.id.
@MainActor
final class AgentStateBus: ObservableObject {
    @Published private(set) var states: [String: AgentState] = [:]
    @Published private(set) var agentTypes: [String: AgentType] = [:]
    private let ipc = HookIPC()

    func start() {
        ipc.onPayload = { [weak self] payload in self?.apply(payload) }
        ipc.start()
    }

    func stop() {
        ipc.stop()
    }

    func state(for worktreePath: String) -> AgentState {
        if let state = states[worktreePath] { return state }
        return states[canonicalPath(worktreePath)] ?? .idle
    }

    func agentType(for worktreePath: String) -> AgentType {
        if let type = agentTypes[worktreePath] { return type }
        return agentTypes[canonicalPath(worktreePath)] ?? .claude
    }

    func reset(for worktreePath: String) {
        states[worktreePath] = .idle
        agentTypes.removeValue(forKey: worktreePath)
        let canonical = canonicalPath(worktreePath)
        if canonical != worktreePath {
            states[canonical] = .idle
            agentTypes.removeValue(forKey: canonical)
        }
    }

    private func apply(_ payload: HookPayload) {
        let path = payload.worktreePath
        let canonical = canonicalPath(path)
        let type: AgentType = payload.agent == "codex" ? .codex : .claude
        agentTypes[path] = type
        if canonical != path { agentTypes[canonical] = type }
        switch payload.state {
        case "running":
            states[path] = .running
            if canonical != path { states[canonical] = .running }

        case "waitingForApproval":
            states[path] = .waitingForApproval
            if canonical != path { states[canonical] = .waitingForApproval }

        case "done":
            states[path] = .done
            if canonical != path { states[canonical] = .done }

        default:
            states[path] = .idle
            if canonical != path { states[canonical] = .idle }
        }
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

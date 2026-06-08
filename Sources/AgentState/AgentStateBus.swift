import Foundation

/// Aggregates agent state events from HookIPC and publishes per-worktree state.
/// Key is the worktree path, which matches GitWorktree.id.
@MainActor
final class AgentStateBus: ObservableObject {
    @Published private(set) var states: [String: AgentState] = [:]
    private let ipc = HookIPC()

    func start() {
        ipc.onPayload = { [weak self] payload in self?.apply(payload) }
        ipc.start()
    }

    func stop() {
        ipc.stop()
    }

    func state(for worktreePath: String) -> AgentState {
        states[worktreePath] ?? .idle
    }

    func reset(for worktreePath: String) {
        states[worktreePath] = .idle
    }

    private func apply(_ payload: HookPayload) {
        let path = payload.worktreePath
        switch payload.state {
        case "running":
            states[path] = .running
        case "done":
            states[path] = .done
        default:
            states[path] = .idle
        }
    }
}

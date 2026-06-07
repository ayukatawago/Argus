import Foundation

/// Aggregates agent state events from HookIPC and publishes per-worktree state.
/// Key is the worktree path, which matches GitWorktree.id.
@MainActor
final class AgentStateBus: ObservableObject {
    @Published private(set) var states: [String: AgentState] = [:]
    private var doneTimers: [String: Task<Void, Never>] = [:]
    private let ipc = HookIPC()

    func start() {
        ipc.onPayload = { [weak self] payload in self?.apply(payload) }
        ipc.start()
    }

    func stop() {
        doneTimers.values.forEach { $0.cancel() }
        doneTimers.removeAll()
        ipc.stop()
    }

    func state(for worktreePath: String) -> AgentState {
        states[worktreePath] ?? .idle
    }

    func reset(for worktreePath: String) {
        cancelDoneTimer(for: worktreePath)
        states[worktreePath] = .idle
    }

    private func apply(_ payload: HookPayload) {
        let path = payload.worktreePath
        switch payload.state {
        case "running":
            cancelDoneTimer(for: path)
            states[path] = .running

        case "done":
            states[path] = .done
            scheduleDoneTimer(for: path)

        default:
            cancelDoneTimer(for: path)
            states[path] = .idle
        }
    }

    private func cancelDoneTimer(for path: String) {
        doneTimers[path]?.cancel()
        doneTimers.removeValue(forKey: path)
    }

    private func scheduleDoneTimer(for path: String) {
        cancelDoneTimer(for: path)
        let timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.states[path] = .idle
            self?.doneTimers.removeValue(forKey: path)
        }
        doneTimers[path] = timer
    }
}

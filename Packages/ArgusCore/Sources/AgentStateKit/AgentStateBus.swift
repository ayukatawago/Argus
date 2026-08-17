import Foundation

/// Aggregates agent state events from HookIPC and publishes per-worktree state.
/// Key is the worktree path, which matches GitWorktree.id.
@MainActor
public final class AgentStateBus: ObservableObject {
    @Published public private(set) var states: [String: AgentState] = [:]
    @Published public private(set) var agentTypes: [String: AgentType] = [:]
    private let ipc = HookIPC()
    private let codexWatcher = CodexSessionWatcher()
    private let claudeTranscriptWatcher = ClaudeTranscriptWatcher()

    public init() {}

    public func start() {
        ipc.onPayload = { [weak self] payload in self?.apply(payload) }
        ipc.start()
        codexWatcher.onPayload = { [weak self] payload in self?.apply(payload) }
        codexWatcher.start()
        claudeTranscriptWatcher.onPayload = { [weak self] payload in self?.apply(payload) }
        claudeTranscriptWatcher.start()
    }

    public func stop() {
        ipc.stop()
        codexWatcher.stop()
        claudeTranscriptWatcher.stop()
    }

    public func state(for worktreePath: String) -> AgentState {
        if let state = states[worktreePath] { return state }
        return states[canonicalPath(worktreePath)] ?? .idle
    }

    public func agentType(for worktreePath: String) -> AgentType {
        if let type = agentTypes[worktreePath] { return type }
        return agentTypes[canonicalPath(worktreePath)] ?? .claude
    }

    public func setAgentType(_ type: AgentType, for worktreePath: String) {
        let canonical = canonicalPath(worktreePath)
        updateAgentType(type, path: worktreePath, canonical: canonical)
    }

    public func reset(for worktreePath: String) {
        let canonical = canonicalPath(worktreePath)
        updateState(.idle, path: worktreePath, canonical: canonical)
        if agentTypes[worktreePath] != nil { agentTypes.removeValue(forKey: worktreePath) }
        if canonical != worktreePath, agentTypes[canonical] != nil {
            agentTypes.removeValue(forKey: canonical)
        }
    }

    // Internal (not private) so tests can drive the reducer directly via @testable import,
    // without going through the socket/file-tailing IPC plumbing in start().
    func apply(_ payload: HookPayload) {
        let path = payload.worktreePath
        let canonical = canonicalPath(path)
        let type: AgentType = payload.agent == "codex" ? .codex : .claude
        updateAgentType(type, path: path, canonical: canonical)

        let newState: AgentState =
            switch payload.state {
            case "running": .running
            case "waitingForApproval": .waitingForApproval
            case "done": .done
            default: .idle
            }
        updateState(newState, path: path, canonical: canonical)
    }

    // `@Published` fires `objectWillChange` on assignment, not on change, so every one of these
    // was republishing (and invalidating the whole sidebar, which observes this bus) even when the
    // hook/watcher re-asserted a state or type it had already reported — up to 4 emissions per
    // payload (state + type, path + canonical). Guarding each write is what keeps a repeated,
    // identical event from causing visible churn downstream.
    private func updateState(_ state: AgentState, path: String, canonical: String) {
        if states[path] != state { states[path] = state }
        if canonical != path, states[canonical] != state { states[canonical] = state }
    }

    private func updateAgentType(_ type: AgentType, path: String, canonical: String) {
        if agentTypes[path] != type { agentTypes[path] = type }
        if canonical != path, agentTypes[canonical] != type { agentTypes[canonical] = type }
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

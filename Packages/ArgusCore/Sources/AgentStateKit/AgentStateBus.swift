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
        agentTypes[worktreePath] = type
        let canonical = canonicalPath(worktreePath)
        if canonical != worktreePath { agentTypes[canonical] = type }
    }

    public func reset(for worktreePath: String) {
        states[worktreePath] = .idle
        agentTypes.removeValue(forKey: worktreePath)
        let canonical = canonicalPath(worktreePath)
        if canonical != worktreePath {
            states[canonical] = .idle
            agentTypes.removeValue(forKey: canonical)
        }
    }

    // Internal (not private) so tests can drive the reducer directly via @testable import,
    // without going through the socket/file-tailing IPC plumbing in start().
    func apply(_ payload: HookPayload) {
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

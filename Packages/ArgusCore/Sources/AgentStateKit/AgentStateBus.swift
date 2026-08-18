import Foundation

/// Aggregates agent state events from HookIPC and publishes per-(worktree, agent) state. Worktree
/// path matches GitWorktree.id.
@MainActor
public final class AgentStateBus: ObservableObject {
    @Published public private(set) var states: [AgentKey: AgentState] = [:]
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

    // MARK: - Reads

    public func state(for worktreePath: String, agent: AgentType) -> AgentState {
        let key = AgentKey(worktreePath: worktreePath, agent: agent)
        if let state = states[key] { return state }
        let canonicalKey = AgentKey(worktreePath: canonicalPath(worktreePath), agent: agent)
        return states[canonicalKey] ?? .idle
    }

    public func statesByAgent(for worktreePath: String) -> [AgentType: AgentState] {
        Dictionary(uniqueKeysWithValues: AgentType.allCases.map { ($0, state(for: worktreePath, agent: $0)) })
    }

    /// The single state + agent identity a worktree-level indicator shows — see
    /// `WorktreeAgentState.aggregate`.
    public func worktreeState(for worktreePath: String) -> WorktreeAgentState {
        WorktreeAgentState.aggregate(statesByAgent(for: worktreePath))
    }

    // MARK: - Writes

    /// Returns every agent for `worktreePath` to `.idle`. Used when a worktree's panes are
    /// released — every agent for it is gone.
    public func reset(for worktreePath: String) {
        let canonical = canonicalPath(worktreePath)
        for agent in AgentType.allCases {
            updateState(
                .idle, key: AgentKey(worktreePath: worktreePath, agent: agent),
                canonicalKey: AgentKey(worktreePath: canonical, agent: agent))
        }
    }

    /// Returns one agent for `worktreePath` to `.idle`. Used by the leader-`a` reload and agent-tab
    /// close, both of which kill one specific agent's tmux session and must not disturb the other.
    public func reset(for worktreePath: String, agent: AgentType) {
        let canonical = canonicalPath(worktreePath)
        updateState(
            .idle, key: AgentKey(worktreePath: worktreePath, agent: agent),
            canonicalKey: AgentKey(worktreePath: canonical, agent: agent))
    }

    /// Clears only the attention states (`.done`, `.waitingForApproval`) for every agent of
    /// `worktreePath`, leaving a `.running` agent alone. The "user interacted with the workspace,
    /// dismiss the border" path — worktree-wide in reach, but must not silently stop a
    /// concurrently running agent from reporting as running.
    public func dismissAttentionStates(for worktreePath: String) {
        let canonical = canonicalPath(worktreePath)
        for agent in AgentType.allCases {
            let key = AgentKey(worktreePath: worktreePath, agent: agent)
            let canonicalKey = AgentKey(worktreePath: canonical, agent: agent)
            guard states[key] == .done || states[key] == .waitingForApproval else { continue }
            updateState(.idle, key: key, canonicalKey: canonicalKey)
        }
    }

    // Internal (not private) so tests can drive the reducer directly via @testable import,
    // without going through the socket/file-tailing IPC plumbing in start().
    func apply(_ payload: HookPayload) {
        guard let agent = AgentType(hookAgent: payload.agent) else { return }
        let path = payload.worktreePath
        let canonical = canonicalPath(path)
        updateState(
            AgentState(hookState: payload.state),
            key: AgentKey(worktreePath: path, agent: agent),
            canonicalKey: AgentKey(worktreePath: canonical, agent: agent)
        )
    }

    // `@Published` fires `objectWillChange` on assignment, not on change, so writing the same
    // state that's already there would republish (and invalidate the whole sidebar, which
    // observes this bus) even when the hook/watcher re-asserted a state it had already reported —
    // up to 2 emissions per payload (raw path + canonical path). Guarding each write is what keeps
    // a repeated, identical event from causing visible churn downstream.
    private func updateState(_ state: AgentState, key: AgentKey, canonicalKey: AgentKey) {
        if states[key] != state { states[key] = state }
        if canonicalKey != key, states[canonicalKey] != state { states[canonicalKey] = state }
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

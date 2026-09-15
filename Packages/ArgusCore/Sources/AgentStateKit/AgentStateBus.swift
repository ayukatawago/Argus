import Foundation

/// Which producer an `apply(_:source:)` call came from, used to arbitrate between them for the
/// same `AgentKey`. Display scraping (`App/AgentPaneDisplayWatcher.swift`) is the primary signal
/// for any pane Argus itself hosts — it reads what the TUI renders continuously, so it isn't
/// subject to transcript/rollout inference's 15-minute staleness heuristic (see
/// `ClaudeTranscriptWatcher.activityWindow`'s doc comment for the false-idle bug that motivates
/// this). Transcript/rollout inference remains the fallback for a worktree with no live Argus
/// agent pane (an agent started in an external terminal, or a tab not yet opened).
public enum StateSource: Sendable {
    /// `ClaudeTranscriptWatcher` / `CodexSessionWatcher` — inferred from a log of past events, so
    /// it's suppressed for any key `.display` currently covers.
    case inference
    /// `AgentPaneDisplayWatcher` (App/) — read from the live tmux pane. Wins over `.inference`.
    case display
    /// `HookIPC`'s `PermissionRequest` hook — never suppressed; nothing else fires while a
    /// permission dialog is open.
    case hook
}

/// Aggregates agent state events from HookIPC and publishes per-(worktree, agent) state. Worktree
/// path matches GitWorktree.id.
@MainActor
public final class AgentStateBus: ObservableObject {
    @Published public private(set) var states: [AgentKey: AgentState] = [:]
    private let ipc = HookIPC()
    private let codexWatcher = CodexSessionWatcher()
    private let claudeTranscriptWatcher = ClaudeTranscriptWatcher()

    /// Keys `AgentPaneDisplayWatcher` currently has a live tmux pane for — published fresh every
    /// poll via `setDisplayCovered(_:)`. `.inference` payloads for a covered key are dropped in
    /// `apply(_:source:)` rather than raced against the display signal.
    private var displayCovered: Set<AgentKey> = []

    /// Consecutive `.display` polls that have reported something other than `waitingForApproval`
    /// while that state is still the one published for this key — see `resolveDisplayDowngrade`.
    private var pendingApprovalDowngrade: [AgentKey: Int] = [:]

    public init() {}

    public func start() {
        ipc.onPayload = { [weak self] payload in self?.apply(payload, source: .hook) }
        ipc.start()
        codexWatcher.onPayload = { [weak self] payload in self?.apply(payload, source: .inference) }
        codexWatcher.start()
        claudeTranscriptWatcher.onPayload = { [weak self] payload in self?.apply(payload, source: .inference) }
        claudeTranscriptWatcher.start()
    }

    /// Called every poll by `AgentPaneDisplayWatcher` (App/, which alone can see live tmux panes —
    /// AgentStateKit cannot import GhosttyBridge) with the full, current set of keys it has a pane
    /// for. Replaces the previous set wholesale rather than merging, so a pane that disappears
    /// (agent tab closed) stops being covered on the very next poll instead of lingering forever.
    public func setDisplayCovered(_ keys: Set<AgentKey>) {
        displayCovered = keys
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
            let key = AgentKey(worktreePath: worktreePath, agent: agent)
            let canonicalKey = AgentKey(worktreePath: canonical, agent: agent)
            pendingApprovalDowngrade[key] = nil
            pendingApprovalDowngrade[canonicalKey] = nil
            updateState(.idle, key: key, canonicalKey: canonicalKey)
        }
    }

    /// Returns one agent for `worktreePath` to `.idle`. Used by the leader-`a` reload and agent-tab
    /// close, both of which kill one specific agent's tmux session and must not disturb the other.
    public func reset(for worktreePath: String, agent: AgentType) {
        let canonical = canonicalPath(worktreePath)
        let key = AgentKey(worktreePath: worktreePath, agent: agent)
        let canonicalKey = AgentKey(worktreePath: canonical, agent: agent)
        pendingApprovalDowngrade[key] = nil
        pendingApprovalDowngrade[canonicalKey] = nil
        updateState(.idle, key: key, canonicalKey: canonicalKey)
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
            // This is an explicit user dismissal, not a display-inferred downgrade — bypasses the
            // debounce below (and clears its counter) rather than waiting for two quiet polls.
            pendingApprovalDowngrade[key] = nil
            pendingApprovalDowngrade[canonicalKey] = nil
            updateState(.idle, key: key, canonicalKey: canonicalKey)
        }
    }

    /// Public (not internal) because `AgentPaneDisplayWatcher` (App/) calls this across the module
    /// boundary — AgentStateKit cannot depend on GhosttyBridge, so the display watcher itself has
    /// to live one layer up, same reasoning as `ShellStateBus`. `source` defaults to `.hook` so
    /// existing tests driving the reducer directly via `@testable import` (bypassing the
    /// socket/file-tailing IPC plumbing in `start()`) don't need updating.
    public func apply(_ payload: HookPayload, source: StateSource = .hook) {
        guard let agent = AgentType(hookAgent: payload.agent) else { return }
        let path = payload.worktreePath
        let canonical = canonicalPath(path)
        let key = AgentKey(worktreePath: path, agent: agent)
        let canonicalKey = AgentKey(worktreePath: canonical, agent: agent)

        // Transcript/rollout inference is the fallback source; once the display watcher covers
        // this key, its payloads are stale by construction (see StateSource's doc comment) and
        // must not race the live signal.
        if source == .inference, displayCovered.contains(key) || displayCovered.contains(canonicalKey) {
            return
        }

        let incoming = AgentState(hookState: payload.state)
        let resolved =
            source == .display
            ? resolveDisplayDowngrade(incoming, key: key, canonicalKey: canonicalKey)
            : incoming
        updateState(resolved, key: key, canonicalKey: canonicalKey)
    }

    /// A pane with an open approval dialog shows no active spinner — indistinguishable, purely
    /// from the display signal, from "the agent simply hasn't resumed yet". Demoting
    /// `waitingForApproval` straight to whatever `.display` reports next would race the
    /// `PermissionRequest` hook exactly while the dialog is still open, the same hazard
    /// `ClaudeTranscriptParser`'s `stop_reason: tool_use` handling exists to avoid. Requiring two
    /// consecutive non-approval `.display` polls before downgrading gives the hook's own
    /// dismissal — or a slow poll cycle — room to land first.
    private func resolveDisplayDowngrade(_ incoming: AgentState, key: AgentKey, canonicalKey: AgentKey) -> AgentState {
        let currentlyWaiting = states[key] == .waitingForApproval || states[canonicalKey] == .waitingForApproval
        guard currentlyWaiting, incoming != .waitingForApproval else {
            pendingApprovalDowngrade[key] = nil
            return incoming
        }
        let pollsWithoutApproval = (pendingApprovalDowngrade[key] ?? 0) + 1
        guard pollsWithoutApproval >= 2 else {
            pendingApprovalDowngrade[key] = pollsWithoutApproval
            return .waitingForApproval
        }
        pendingApprovalDowngrade[key] = nil
        return incoming
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

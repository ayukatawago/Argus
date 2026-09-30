import Foundation

/// The single state + agent identity a worktree-level indicator (sidebar dot/row, window tint)
/// shows for a worktree that may have both a Claude and a Codex session.
public struct WorktreeAgentState: Equatable, Sendable {
    public let state: AgentState
    public let agent: AgentType

    public static let idle = WorktreeAgentState(state: .idle, agent: .claude)

    public init(state: AgentState, agent: AgentType) {
        self.state = state
        self.agent = agent
    }

    /// Highest `AgentState.displayPriority` wins. Ties (both agents in the same state) resolve to
    /// the first entry in `AgentType.allCases` (Claude) — deliberately not the configured default
    /// agent, since this aggregate has no access to per-worktree layout/config context and
    /// deriving the color from config would flip every row's color whenever the user changes it.
    /// Agent identity is only visible on screen while `state == .running` (every other state's
    /// color is agent-independent), so a tie is only observable while both agents are running at
    /// once. An empty input returns `.idle`.
    public static func aggregate(_ states: [AgentType: AgentState]) -> WorktreeAgentState {
        var best = WorktreeAgentState.idle
        for agent in AgentType.allCases {
            let state = states[agent] ?? .idle
            if state.displayPriority > best.state.displayPriority {
                best = WorktreeAgentState(state: state, agent: agent)
            }
        }
        return best
    }
}

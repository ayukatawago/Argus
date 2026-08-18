import Foundation

public enum AgentState: Equatable, Sendable {
    case idle
    case running
    case waitingForApproval
    case done

    /// Higher wins when one worktree-level indicator has to stand in for several agents — see
    /// `WorktreeAgentState.aggregate`. waitingForApproval is blocking the user, done is awaiting a
    /// reply, running is merely informational.
    public var displayPriority: Int {
        switch self {
        case .idle: 0
        case .running: 1
        case .done: 2
        case .waitingForApproval: 3
        }
    }

    /// Maps a `HookPayload.state` string. Any unrecognized value (including the literal "idle")
    /// maps to `.idle`.
    public init(hookState raw: String) {
        switch raw {
        case "running": self = .running
        case "waitingForApproval": self = .waitingForApproval
        case "done": self = .done
        default: self = .idle
        }
    }
}

public enum AgentType: Equatable, Hashable, CaseIterable, Sendable {
    // Declaration order is `WorktreeAgentState.aggregate`'s tie-break order — do not reorder.
    case claude
    case codex

    /// Maps a `HookPayload.agent` string. `nil` for a producer that isn't an agent pane (the fish
    /// shell hooks tag their events `"shell"`) or an unrecognized identifier — callers should drop
    /// the payload rather than attribute it to a guessed agent. A missing field maps to `.claude`:
    /// the only producer that ever omitted it was Argus's own hook script before the `agent` field
    /// existed.
    public init?(hookAgent raw: String?) {
        switch raw {
        case "codex": self = .codex
        case "claude", nil: self = .claude
        default: return nil
        }
    }
}

/// Identifies one agent's state within one worktree.
public struct AgentKey: Hashable, Sendable {
    public let worktreePath: String
    public let agent: AgentType

    public init(worktreePath: String, agent: AgentType) {
        self.worktreePath = worktreePath
        self.agent = agent
    }
}

public struct HookPayload: Decodable, Sendable {
    public let worktreePath: String
    public let state: String
    public let agent: String?

    public init(worktreePath: String, state: String, agent: String?) {
        self.worktreePath = worktreePath
        self.state = state
        self.agent = agent
    }
}

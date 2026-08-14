import Foundation

public enum AgentState: Equatable, Sendable {
    case idle
    case running
    case waitingForApproval
    case done
}

public enum AgentType: Equatable, Sendable {
    case claude
    case codex
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

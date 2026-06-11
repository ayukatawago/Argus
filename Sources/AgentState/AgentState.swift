import Foundation

enum AgentState: Equatable, Sendable {
    case idle
    case running
    case waitingForApproval
    case done
}

enum AgentType: Equatable, Sendable {
    case claude
    case codex
}

struct HookPayload: Decodable, Sendable {
    let worktreePath: String
    let state: String
    let agent: String?
}

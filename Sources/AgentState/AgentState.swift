import Foundation

enum AgentState: Equatable, Sendable {
    case idle
    case running
    case waitingForApproval
    case done
}

struct HookPayload: Decodable, Sendable {
    let worktreePath: String
    let state: String
}

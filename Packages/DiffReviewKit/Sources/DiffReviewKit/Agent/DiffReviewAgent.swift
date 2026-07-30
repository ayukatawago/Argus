import Foundation

/// Which CLI agent to invoke for review actions, and how to invoke it.
public struct DiffReviewAgent: Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case claude
        case codex

        public var displayName: String {
            switch self {
            case .claude: "Claude Code"
            case .codex: "Codex"
            }
        }
    }

    public let kind: Kind
    /// Path to the CLI executable. When `nil`, the bare command name is used and resolved via the
    /// login shell's `PATH` (matches how popup terminals resolve user-installed tools elsewhere).
    public var executablePath: String?
    /// Extra environment variables merged over the current process environment.
    public var environmentOverrides: [String: String]

    public init(kind: Kind, executablePath: String? = nil, environmentOverrides: [String: String] = [:]) {
        self.kind = kind
        self.executablePath = executablePath
        self.environmentOverrides = environmentOverrides
    }
}

/// Whether a headless agent run may modify files.
public enum AgentRunMode: Sendable {
    /// The agent should answer without touching the working tree.
    case reply
    /// The agent should make the requested change; edits are auto-accepted in the worktree.
    case apply
}

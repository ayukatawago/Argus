import Foundation

/// The terminal role a pane serves within a worktree.
public enum PaneRole: Sendable {
    case shell
    case claude
    case codex

    /// The single-character tmux session type used by `TmuxSessionName.make(type:path:)` — the
    /// one definition every session-naming call site should route through, instead of repeating
    /// the "s"/"a"/"x" literals.
    public var tmuxSessionType: String {
        switch self {
        case .shell: "s"
        case .claude: "a"
        case .codex: "x"
        }
    }

    /// The agent this role hosts, or `nil` for `.shell`.
    public var agent: AgentSelection? {
        switch self {
        case .shell: nil
        case .claude: .claude
        case .codex: .codex
        }
    }
}

extension AgentSelection {
    /// The pane role this agent selection is rendered into.
    public var paneRole: PaneRole {
        switch self {
        case .claude: .claude
        case .codex: .codex
        }
    }
}

import Foundation

/// The terminal role a pane serves within a worktree.
public enum PaneRole: Sendable {
    case shell
    case claude
    case codex
}

import Foundation

/// Pure layout-selection rules: which pane roles a `WindowLayout` × `AgentSelection` combination
/// needs, which one is "primary", and their left-to-right/top-to-bottom order. Moved out of
/// PanePool so it can be tested without spinning up terminal panes.
public enum PaneLayoutResolver {
    /// The roles that must be registered for a given layout + agent selection.
    public static func requiredRoles(layout: WindowLayout, agent: AgentSelection) -> [PaneRole] {
        switch layout {
        case .terminalAgent:
            return [.shell, agent == .codex ? .codex : .claude]

        case .agentsOverTerminal, .terminalClaudeCodex:
            return [.shell, .claude, .codex]
        }
    }

    /// The primary agent role (determines which session canvas attaches to and which
    /// session reload targets).
    public static func primaryAgentRole(layout: WindowLayout, agent: AgentSelection) -> PaneRole {
        switch layout {
        case .terminalAgent:
            return agent == .codex ? .codex : .claude

        case .agentsOverTerminal, .terminalClaudeCodex:
            return .claude
        }
    }

    /// Left-to-right (then top-to-bottom) pane order used for directional focus.
    public static func orderedRoles(layout: WindowLayout, agent: AgentSelection) -> [PaneRole] {
        switch layout {
        case .terminalAgent:
            return [.shell, agent == .codex ? .codex : .claude]

        case .agentsOverTerminal:
            // Top-left Codex, top-right Claude, bottom Shell
            return [.codex, .claude, .shell]

        case .terminalClaudeCodex:
            return [.shell, .claude, .codex]
        }
    }
}

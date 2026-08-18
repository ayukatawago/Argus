import Foundation

/// Pure layout-selection rules: which pane roles a worktree's open agent tabs need registered,
/// which are visible right now, and their left-to-right/top-to-bottom order. Moved out of
/// PanePool so it can be tested without spinning up terminal panes.
///
/// `requiredRoles`/`visibleAgentRoles` no longer take a `WindowLayout`: both remaining layouts
/// show the shell pane plus one agent view, so which roles exist is purely a function of the
/// worktree's open/visible agent tabs, not of which layout is selected.
public enum PaneLayoutResolver {
    /// Every role that must stay registered for a worktree — every *open* agent tab, visible or
    /// not (a hidden tab keeps its agent running, like a background tmux window), plus the shell.
    public static func requiredRoles(tabs: AgentTabs) -> [PaneRole] {
        [.shell] + tabs.open.map(\.paneRole)
    }

    /// The agent panes the agent view renders right now. Degenerates correctly: split with only
    /// one open tab is the same as full.
    public static func visibleAgentRoles(tabs: AgentTabs, mode: AgentPaneMode) -> [PaneRole] {
        switch mode {
        case .full: [tabs.active.paneRole]
        case .split: tabs.open.map(\.paneRole)
        }
    }

    /// Left-to-right (then top-to-bottom) pane order used for directional focus. Only *visible*
    /// panes participate — a hidden tab is reached with the tab bindings, not directional focus.
    public static func orderedRoles(layout: WindowLayout, tabs: AgentTabs, mode: AgentPaneMode) -> [PaneRole] {
        let agents = visibleAgentRoles(tabs: tabs, mode: mode)
        switch layout {
        case .terminalAgent: return [.shell] + agents
        case .agentsOverTerminal: return agents + [.shell]
        }
    }
}

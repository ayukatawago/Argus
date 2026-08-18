import AgentStateKit
import ArgusConfigKit
import SwiftUI

/// The agent view: a tab bar over the worktree's open agent tabs (Claude/Codex), above either a
/// single visible pane (full-width mode) or both side by side (split mode) — see
/// `PaneLayoutResolver.visibleAgentRoles`.
struct AgentPaneView: View {
    @ObservedObject var agentTabs: AgentTabsStore
    @ObservedObject var agentBus: AgentStateBus
    @ObservedObject var claudeHost: TerminalHost
    @ObservedObject var codexHost: TerminalHost
    var worktreePath: String
    /// Called after a tab action changes which agent is active, with the pane role that should
    /// receive focus.
    var onActivated: (PaneRole) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            AgentTabBarView(
                store: agentTabs, agentBus: agentBus, worktreePath: worktreePath, onActivate: onActivated)
            panes
        }
    }

    @ViewBuilder
    private var panes: some View {
        let visible = PaneLayoutResolver.visibleAgentRoles(tabs: agentTabs.tabs, mode: agentTabs.mode)
        if visible.count > 1 {
            HSplitView {
                ForEach(visible, id: \.self) { role in
                    hostView(for: role)
                        .frame(minWidth: 200)
                }
            }
        } else if let role = visible.first {
            hostView(for: role)
        }
    }

    private func host(for role: PaneRole) -> TerminalHost {
        role == .codex ? codexHost : claudeHost
    }

    @ViewBuilder
    private func hostView(for role: PaneRole) -> some View {
        let host = host(for: role)
        let state = role.agent.map { agentBus.state(for: worktreePath, agent: $0.agentType) } ?? .idle
        // `.id(role)` is required, not cosmetic: in full mode this is the only view in its slot,
        // so without a role-keyed identity a Claude<->Codex switch would leave `TerminalHostView`
        // stuck on whichever host was mounted first — see its doc comment.
        TerminalHostView(host: host)
            .focusBorder(isFocused: host.hasFocus)
            .agentStateBorder(state)
            .id(role)
    }
}

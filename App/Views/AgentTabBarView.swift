import AgentStateKit
import ArgusConfigKit
import SwiftUI

/// Tab bar over `AgentTabsStore`'s open agent tabs — the agent-pane analogue of
/// `TerminalTabBarView`, matched metric for metric so the two bars align across the split in the
/// `terminalAgent` layout. Unlike the terminal tab bar this is not a tmux mirror: opening/closing a
/// tab is Argus state, not a tmux command (see `AgentTabsStore`'s doc comment).
struct AgentTabBarView: View {
    @ObservedObject var store: AgentTabsStore
    @ObservedObject var agentBus: AgentStateBus
    var worktreePath: String
    /// Called after an action changes which tab is active, with the pane role that should receive
    /// focus — mirrors `TerminalTabBarView.onActivate`.
    var onActivate: (PaneRole) -> Void = { _ in }

    @State private var hoveredAgent: AgentSelection?

    private static var barHeight: CGFloat { 32 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(store.tabs.open) { agent in
                            chip(for: agent)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                newTabButton
                Spacer(minLength: 0)
            }
            .frame(height: Self.barHeight)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
        }
    }

    private func chip(for agent: AgentSelection) -> some View {
        let isActive = store.tabs.active == agent
        return HStack(spacing: 6) {
            AgentDot(state: agentBus.state(for: worktreePath, agent: agent.agentType), agentType: agent.agentType)
            Text(agent.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
            if hoveredAgent == agent, store.tabs.open.count > 1 {
                Button {
                    close(agent)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Close \(agent.displayName) tab")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering in hoveredAgent = isHovering ? agent : nil }
        .onTapGesture { select(agent) }
        .contentShape(Rectangle())
        .contextMenu {
            if store.tabs.open.count > 1 {
                Button("Close \(agent.displayName) Tab") { close(agent) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(agent) }
    }

    @ViewBuilder
    private var newTabButton: some View {
        if store.tabs.closed != nil {
            Button(action: openClosed) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: Self.barHeight, height: Self.barHeight)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Open \(store.tabs.closed?.displayName ?? "agent") tab")
        }
    }

    private func select(_ agent: AgentSelection) {
        guard store.select(agent) else { return }
        onActivate(agent.paneRole)
    }

    private func openClosed() {
        guard store.openClosedTab() else { return }
        onActivate(store.tabs.active.paneRole)
    }

    private func close(_ agent: AgentSelection) {
        let task = store.closeTab(agent)
        Task {
            await task.value
            onActivate(store.tabs.active.paneRole)
        }
    }
}

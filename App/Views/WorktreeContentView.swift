import SwiftUI

struct WorktreeContentView: View {
    var layout: WindowLayout
    var agent: AgentSelection
    @ObservedObject var shellHost: TerminalHost
    @ObservedObject var claudeHost: TerminalHost
    @ObservedObject var codexHost: TerminalHost
    var agentState: AgentState = .idle

    var body: some View {
        switch layout {
        case .terminalAgent:
            terminalAgentLayout

        case .agentsOverTerminal:
            agentsOverTerminalLayout

        case .terminalClaudeCodex:
            terminalClaudeCodexLayout
        }
    }

    // MARK: - Layout variants

    /// Left: terminal. Right: the currently-selected agent (Claude or Codex).
    @ViewBuilder
    private var terminalAgentLayout: some View {
        let agentHost = agent == .codex ? codexHost : claudeHost
        HSplitView {
            TerminalHostView(host: shellHost)
                .overlay(focusBorder(isFocused: shellHost.hasFocus))
                .frame(minWidth: 200)
            TerminalHostView(host: agentHost)
                .overlay(focusBorder(isFocused: agentHost.hasFocus))
                .overlay(agentStateBorder)
                .frame(minWidth: 200)
        }
    }

    /// Top row: Codex (left) + Claude Code (right). Bottom: full-width terminal.
    @ViewBuilder
    private var agentsOverTerminalLayout: some View {
        VSplitView {
            HSplitView {
                TerminalHostView(host: codexHost)
                    .overlay(focusBorder(isFocused: codexHost.hasFocus))
                    .frame(minWidth: 200)
                TerminalHostView(host: claudeHost)
                    .overlay(focusBorder(isFocused: claudeHost.hasFocus))
                    .overlay(agentStateBorder)
                    .frame(minWidth: 200)
            }
            .frame(minHeight: 120)
            TerminalHostView(host: shellHost)
                .overlay(focusBorder(isFocused: shellHost.hasFocus))
                .frame(minHeight: 120)
        }
    }

    /// Left: terminal. Center: Claude Code. Right: Codex.
    @ViewBuilder
    private var terminalClaudeCodexLayout: some View {
        HSplitView {
            TerminalHostView(host: shellHost)
                .overlay(focusBorder(isFocused: shellHost.hasFocus))
                .frame(minWidth: 200)
            TerminalHostView(host: claudeHost)
                .overlay(focusBorder(isFocused: claudeHost.hasFocus))
                .overlay(agentStateBorder)
                .frame(minWidth: 200)
            TerminalHostView(host: codexHost)
                .overlay(focusBorder(isFocused: codexHost.hasFocus))
                .frame(minWidth: 200)
        }
    }

    // MARK: - Borders

    @ViewBuilder
    private func focusBorder(isFocused: Bool) -> some View {
        if isFocused {
            Rectangle()
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
        }
    }

    /// State border applied to the primary agent (Claude) pane.
    @ViewBuilder
    private var agentStateBorder: some View {
        switch agentState {
        case .done:
            Rectangle()
                .strokeBorder(Color.green.opacity(0.5), lineWidth: 2)

        case .waitingForApproval:
            Rectangle()
                .strokeBorder(Color.orange.opacity(0.7), lineWidth: 3)

        default:
            EmptyView()
        }
    }
}

private struct TerminalHostView: NSViewRepresentable {
    let host: TerminalHost

    func makeNSView(context _: Context) -> TerminalHost { host }
    func updateNSView(_: TerminalHost, context _: Context) {}
}

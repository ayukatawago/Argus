import SwiftUI

struct WorktreeContentView: View {
    @ObservedObject var shellHost: TerminalHost
    @ObservedObject var agentHost: TerminalHost
    var agentState: AgentState = .idle

    var body: some View {
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

    @ViewBuilder
    private func focusBorder(isFocused: Bool) -> some View {
        if isFocused {
            Rectangle()
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
        }
    }

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

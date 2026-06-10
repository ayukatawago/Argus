import AppKit
import GhosttyTerminal
import SwiftUI

struct CanvasView: View {
    let worktrees: [WorktreeCard]
    let canvasViews: [String: AppTerminalView]
    @ObservedObject var agentBus: AgentStateBus
    let onSelect: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(worktrees, id: \.id) { card in
                    CanvasCardView(
                        name: card.name,
                        branch: card.branch,
                        agentState: agentBus.state(for: card.id),
                        terminalView: canvasViews[card.id]
                    )
                    .onTapGesture { onSelect(card.id) }
                }
            }
            .padding(16)
        }
    }
}

struct CanvasCardView: View {
    let name: String
    let branch: String?
    let agentState: AgentState
    let terminalView: AppTerminalView?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                AgentDot(state: agentState)
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let branch {
                    Text(branch)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))

            if let termView = terminalView {
                CanvasTerminalView(terminal: termView)
                    .frame(height: 200)
            } else {
                Color.secondary.opacity(0.1)
                    .frame(height: 200)
            }
        }
        .background(AgentStateBackground(agentState: agentState, isActive: true, isSelected: false))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct CanvasTerminalView: NSViewRepresentable {
    let terminal: AppTerminalView

    func makeNSView(context _: Context) -> AppTerminalView { terminal }
    func updateNSView(_: AppTerminalView, context _: Context) {}
}

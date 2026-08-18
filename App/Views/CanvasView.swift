import AgentStateKit
import AppKit
import ArgusSupport
import GhosttyTerminal
import SwiftUI

private let canvasPadding: CGFloat = 12
private let canvasSpacing: CGFloat = 8
private let titleBarHeight: CGFloat = 26

struct CanvasView: View {
    let worktrees: [WorktreeCard]
    let canvasViews: [String: AppTerminalView]
    @ObservedObject var agentBus: AgentStateBus
    let onSelect: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let layout = CanvasLayout(
                count: worktrees.count,
                available: geo.size,
                padding: canvasPadding,
                spacing: canvasSpacing,
                titleBarHeight: titleBarHeight
            )
            let gridColumns = Array(
                repeating: GridItem(.fixed(layout.cardWidth), spacing: canvasSpacing),
                count: layout.columns
            )
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: canvasSpacing) {
                    ForEach(worktrees, id: \.id) { card in
                        let worktreeState = agentBus.worktreeState(for: card.id)
                        CanvasCardView(
                            name: card.name,
                            branch: card.branch,
                            agentState: worktreeState.state,
                            agentType: worktreeState.agent,
                            terminalView: canvasViews[card.id],
                            terminalHeight: layout.terminalHeight
                        )
                        .onTapGesture { onSelect(card.id) }
                    }
                }
                .padding(canvasPadding)
            }
        }
    }
}

struct CanvasCardView: View {
    let name: String
    let branch: String?
    let agentState: AgentState
    let agentType: AgentType
    let terminalView: AppTerminalView?
    let terminalHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                AgentDot(state: agentState, agentType: agentType)
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
            .frame(height: titleBarHeight)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            if let termView = terminalView {
                CanvasTerminalView(terminal: termView)
                    .frame(height: terminalHeight)
            } else {
                Color.secondary.opacity(0.1)
                    .frame(height: terminalHeight)
            }
        }
        .background(
            AgentStateBackground(
                agentState: agentState,
                isActive: true,
                isSelected: false,
                agentType: agentType
            )
        )
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

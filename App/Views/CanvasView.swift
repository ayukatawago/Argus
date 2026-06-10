import AppKit
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
            let layout = CanvasLayout(count: worktrees.count, available: geo.size)
            let gridColumns = Array(
                repeating: GridItem(.fixed(layout.cardWidth), spacing: canvasSpacing),
                count: layout.columns
            )
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: canvasSpacing) {
                    ForEach(worktrees, id: \.id) { card in
                        CanvasCardView(
                            name: card.name,
                            branch: card.branch,
                            agentState: agentBus.state(for: card.id),
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

struct CanvasLayout {
    let columns: Int
    let cardWidth: CGFloat
    let terminalHeight: CGFloat

    init(count: Int, available: CGSize) {
        let cols = max(1, Int(ceil(sqrt(Double(max(1, count))))))
        columns = cols

        let totalHPad = canvasPadding * 2 + canvasSpacing * CGFloat(cols - 1)
        cardWidth = max(100, (available.width - totalHPad) / CGFloat(cols))

        let rows = max(1, Int(ceil(Double(count) / Double(cols))))
        let totalVPad = canvasPadding * 2 + canvasSpacing * CGFloat(rows - 1)
        let cardHeight = max(60, (available.height - totalVPad) / CGFloat(rows))
        terminalHeight = max(40, cardHeight - titleBarHeight)
    }

    /// Font size (pt) scaled so roughly 20 lines fit in the terminal area.
    var fontSize: Int { max(7, min(13, Int(terminalHeight / 25.0))) }
}

struct CanvasCardView: View {
    let name: String
    let branch: String?
    let agentState: AgentState
    let terminalView: AppTerminalView?
    let terminalHeight: CGFloat

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

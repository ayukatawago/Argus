import AgentStateKit
import AppKit
import ArgusConfigKit
import SwiftUI

struct WorktreeContentView: View {
    var layout: WindowLayout
    @ObservedObject var shellHost: TerminalHost
    @ObservedObject var claudeHost: TerminalHost
    @ObservedObject var codexHost: TerminalHost
    @ObservedObject var tabsStore: TerminalTabsStore
    @ObservedObject var agentTabs: AgentTabsStore
    @ObservedObject var agentBus: AgentStateBus
    var worktreePath: String
    var onShellActivated: () -> Void = {}
    var onAgentActivated: (PaneRole) -> Void = { _ in }

    var body: some View {
        switch layout {
        case .terminalAgent:
            terminalAgentLayout

        case .agentsOverTerminal:
            agentsOverTerminalLayout
        }
    }

    // MARK: - Layout variants

    /// Left: terminal. Right: the agent view (its own tabs, full-width or split — see
    /// `AgentPaneView`).
    @ViewBuilder
    private var terminalAgentLayout: some View {
        HSplitView {
            shellPane
                .frame(minWidth: 200)
            agentPane
                .frame(minWidth: 200)
        }
    }

    /// Top: the agent view. Bottom: full-width terminal. Initial split is 70% agents / 30%
    /// terminal; the divider remains user-draggable.
    @ViewBuilder
    private var agentsOverTerminalLayout: some View {
        RatioVSplitView(topFraction: 0.7) {
            agentPane
        } bottom: {
            shellPane
        }
    }

    private var agentPane: some View {
        AgentPaneView(
            agentTabs: agentTabs,
            agentBus: agentBus,
            claudeHost: claudeHost,
            codexHost: codexHost,
            worktreePath: worktreePath,
            onActivated: onAgentActivated
        )
    }

    /// The shell column: its tmux windows as a tab bar, above the terminal itself. Extracted so
    /// both layouts pick up the bar from one place. The focus border deliberately stays scoped to
    /// the terminal, not the tab bar above it.
    @ViewBuilder
    private var shellPane: some View {
        VStack(spacing: 0) {
            TerminalTabBarView(store: tabsStore, onActivate: activateShell)
            TerminalHostView(host: shellHost)
                .focusBorder(isFocused: shellHost.hasFocus)
        }
    }

    private func activateShell() {
        onShellActivated()
        shellHost.focusActiveTerminal()
    }
}

/// A vertical split view whose divider starts at a fixed fraction of the available height.
/// Plain SwiftUI `VSplitView` always starts at an even 50/50 split regardless of frame hints,
/// so the initial position is set here by driving `NSSplitView` directly.
private struct RatioVSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    let topFraction: CGFloat
    let top: Top
    let bottom: Bottom

    private static var minPaneHeight: CGFloat { 120 }

    init(topFraction: CGFloat, @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.topFraction = topFraction
        self.top = top()
        self.bottom = bottom()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(topFraction: topFraction)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let topHost = NSHostingView(rootView: top)
        let bottomHost = NSHostingView(rootView: bottom)
        context.coordinator.topHost = topHost
        context.coordinator.bottomHost = bottomHost
        splitView.addArrangedSubview(topHost)
        splitView.addArrangedSubview(bottomHost)
        return splitView
    }

    func updateNSView(_: NSSplitView, context: Context) {
        context.coordinator.topHost?.rootView = top
        context.coordinator.bottomHost?.rootView = bottom
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        let topFraction: CGFloat
        var topHost: NSHostingView<Top>?
        var bottomHost: NSHostingView<Bottom>?
        private var didSetInitialPosition = false

        init(topFraction: CGFloat) {
            self.topFraction = topFraction
        }

        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            splitView.adjustSubviews()
            guard !didSetInitialPosition, splitView.bounds.height > 0 else { return }
            splitView.setPosition(splitView.bounds.height * topFraction, ofDividerAt: 0)
            didSetInitialPosition = true
        }

        func splitView(
            _: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt _: Int
        ) -> CGFloat {
            max(proposedMinimumPosition, RatioVSplitView.minPaneHeight)
        }

        func splitView(
            _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt _: Int
        ) -> CGFloat {
            min(proposedMaximumPosition, splitView.bounds.height - RatioVSplitView.minPaneHeight)
        }
    }
}

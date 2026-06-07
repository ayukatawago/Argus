import AppKit
import SwiftUI

/// Wraps a side-by-side split of two persistent TerminalHost NSViews in SwiftUI.
/// All terminal switching is handled by TerminalHost.activate(id:) — this view
/// does nothing on update because the hosts manage their own subview visibility.
struct WorktreeContentView: NSViewRepresentable {
    let shellHost: TerminalHost
    let agentHost: TerminalHost

    func makeNSView(context _: Context) -> SplitTerminalView {
        SplitTerminalView(shellHost: shellHost, agentHost: agentHost)
    }

    func updateNSView(_: SplitTerminalView, context _: Context) {}
}

final class SplitTerminalView: NSView, NSSplitViewDelegate {
    private let splitView = NSSplitView()
    private var initialPositionSet = false

    init(shellHost: TerminalHost, agentHost: TerminalHost) {
        super.init(frame: .zero)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        splitView.addSubview(shellHost)
        splitView.addSubview(agentHost)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard !initialPositionSet, bounds.width > 0 else { return }
        splitView.setPosition(bounds.width / 2, ofDividerAt: 0)
        initialPositionSet = true
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt _: Int
    ) -> CGFloat { 200 }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt _: Int
    ) -> CGFloat { splitView.bounds.width - 200 }
}

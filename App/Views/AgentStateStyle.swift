import AgentStateKit
import SwiftUI

/// Single source of truth for how an `AgentState` looks and is announced, so the sidebar dot, row
/// border, pane border, tab chip and window tint can't drift apart. Lives in `App/` because
/// `AgentStateKit` is Foundation-only.
extension AgentState {
    var accessibilityText: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .waitingForApproval: "Waiting for approval"
        case .done: "Done"
        }
    }

    /// A shape per state so color is never the only cue.
    var symbolName: String {
        switch self {
        case .idle: "circle"
        case .running: "circle.dotted"
        case .waitingForApproval: "exclamationmark.circle.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    func dotColor(for agentType: AgentType) -> Color {
        switch self {
        case .idle: Color.secondary.opacity(0.4)
        case .running: agentColor(agentType)
        case .waitingForApproval: Color.orange
        case .done: Color.green.opacity(0.8)
        }
    }

    /// Sidebar-row outline for the two "needs the user" states; nil otherwise.
    var rowBorder: (color: Color, lineWidth: CGFloat)? {
        switch self {
        case .done: (Color.green.opacity(0.55), 1.5)
        case .waitingForApproval: (Color.orange.opacity(0.7), 2)
        case .idle, .running: nil
        }
    }

    /// Terminal/agent pane outline for the two "needs the user" states; nil otherwise.
    var paneBorder: (color: Color, lineWidth: CGFloat)? {
        switch self {
        case .done: (Color.green.opacity(0.5), 2)
        case .waitingForApproval: (Color.orange.opacity(0.7), 3)
        case .idle, .running: nil
        }
    }

    /// Faint wash over the whole detail area.
    var detailTint: Color {
        switch self {
        case .done: Color.green.opacity(0.05)
        case .waitingForApproval: Color.orange.opacity(0.07)
        case .idle, .running: Color.clear
        }
    }
}

import AgentStateKit
import SwiftUI

/// Focus/state border overlays shared by every terminal and agent pane.
extension View {
    func focusBorder(isFocused: Bool) -> some View {
        overlay {
            if isFocused {
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    func agentStateBorder(_ state: AgentState) -> some View {
        overlay {
            switch state {
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
}

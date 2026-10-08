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
            if let border = state.paneBorder {
                Rectangle()
                    .strokeBorder(border.color, lineWidth: border.lineWidth)
            }
        }
    }
}

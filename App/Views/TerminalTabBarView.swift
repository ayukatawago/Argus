import Monitors
import SwiftUI

/// Tab bar mirroring the shell session's tmux windows. Purely a control surface over
/// `TerminalTabsStore` — see that type for the tmux commands each action issues.
struct TerminalTabBarView: View {
    @ObservedObject var store: TerminalTabsStore
    /// Called after an action's tmux command completes, so the caller can restore focus to the
    /// terminal and (for select) update which pane role is considered focused.
    var onActivate: () -> Void = {}

    @State private var hoveredIndex: Int?

    private static var barHeight: CGFloat { 32 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(store.windows) { window in
                            chip(for: window)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                newTabButton
                Spacer(minLength: 0)
            }
            .frame(height: Self.barHeight)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
        }
    }

    private func chip(for window: TmuxWindow) -> some View {
        HStack(spacing: 6) {
            Text(window.label)
                .font(.system(size: 13))
                .lineLimit(1)
            if hoveredIndex == window.index, store.windows.count > 1 {
                Button {
                    close(window)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Close \(window.label) tab")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(window.isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering in hoveredIndex = isHovering ? window.index : nil }
        .onTapGesture { select(window) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(window.isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(window) }
    }

    private var newTabButton: some View {
        Button(action: newTab) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .frame(width: Self.barHeight, height: Self.barHeight)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("New terminal tab")
    }

    private func select(_ window: TmuxWindow) {
        guard !window.isActive else { return }
        let task = store.select(index: window.index)
        Task {
            await task.value
            onActivate()
        }
    }

    private func newTab() {
        let task = store.newTab()
        Task {
            await task.value
            onActivate()
        }
    }

    private func close(_ window: TmuxWindow) {
        let task = store.close(index: window.index)
        Task {
            await task.value
            onActivate()
        }
    }
}

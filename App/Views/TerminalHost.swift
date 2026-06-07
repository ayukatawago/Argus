import AppKit
import GhosttyTerminal

/// NSView container that keeps every worktree terminal alive while displaying
/// only one at a time.
///
/// Inactive terminals are physically removed from the view hierarchy, which
/// causes AppTerminalView.viewDidMoveToWindow to fire with window == nil.
/// The library interprets that as occlusion and stops its display link, but
/// it explicitly preserves the ghostty surface and scrollback so the session
/// resumes instantly when the view is re-added.
///
/// Only the active terminal is a subview, ensuring exactly one Metal surface
/// composites on screen at a time.
@MainActor
final class TerminalHost: NSView {
    private var terminals: [String: AppTerminalView] = [:]
    private(set) var activeID: String?

    func activate(id: String?) {
        guard activeID != id else { return }

        if let prev = activeID, let prevView = terminals[prev] {
            prevView.removeFromSuperview()
        }

        activeID = id

        if let id, let next = terminals[id] {
            mount(next)
        }
    }

    func register(id: String, terminal: AppTerminalView) {
        guard terminals[id] == nil else { return }
        terminals[id] = terminal
        if id == activeID {
            mount(terminal)
        }
    }

    private func mount(_ terminal: AppTerminalView) {
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}

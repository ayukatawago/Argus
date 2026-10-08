import AppKit
import ArgusConfigKit
import DiffReviewKit
import SwiftUI

/// Manages a single floating NSWindow hosting the `DiffReviewKit` side-by-side review UI for one
/// worktree at a time, sized as a large popup (like `PopupTerminalWindow`) rather than a regular
/// document window. An `ObservableObject` owning a lazily-created `NSWindow`, reused (and
/// refocused) on repeat opens for the same worktree, recreated for a different one.
@MainActor
final class DiffReviewWindow: NSObject, NSWindowDelegate, ObservableObject {
    private var window: NSWindow?
    private var currentWorktreePath: String?
    private var currentBase: String?
    private var currentHead: String?

    /// - Parameters:
    ///   - base: initial base ref (empty auto-resolves the default branch, see
    ///     `DiffReviewView.initialBase`).
    ///   - head: initial head ref, defaulting to `HEAD`.
    func open(worktreePath: String, base: String = "", head: String = "HEAD", agent: AgentSelection) {
        if currentWorktreePath == worktreePath, currentBase == base, currentHead == head, let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Any previous window (a different worktree, or the same one with different refs) would
        // otherwise be orphaned on screen instead of replaced.
        window?.close()

        let reviewAgent = DiffReviewAgent(kind: agent == .codex ? .codex : .claude)
        let hosting = NSHostingView(
            rootView: DiffReviewView(
                repositoryPath: worktreePath,
                initialBase: base,
                initialHead: head,
                agent: reviewAgent
            )
        )

        let screenFrame = NSScreen.popupVisibleFrame
        let size = CGSize(width: screenFrame.width * 0.95, height: screenFrame.height * 0.95)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Review: \(URL(fileURLWithPath: worktreePath).lastPathComponent)"
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.contentView = hosting
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
        currentWorktreePath = worktreePath
        currentBase = base
        currentHead = head
    }

    func windowWillClose(_: Notification) {
        window = nil
        currentWorktreePath = nil
        currentBase = nil
        currentHead = nil
    }
}

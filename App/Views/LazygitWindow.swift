import AppKit
import GhosttyTerminal

extension Notification.Name {
    static let openLazygit = Notification.Name("kotty.openLazygit")
    static let focusShellPane = Notification.Name("kotty.focusShellPane")
    static let focusAgentPane = Notification.Name("kotty.focusAgentPane")
    static let selectNextWorktree = Notification.Name("kotty.selectNextWorktree")
    static let selectPreviousWorktree = Notification.Name("kotty.selectPreviousWorktree")
    static let refreshWorkspace = Notification.Name("kotty.refreshWorkspace")
    static let workspaceInteracted = Notification.Name("kotty.workspaceInteracted")
    static let openMarkdownPreview = Notification.Name("kotty.openMarkdownPreview")
}

/// Manages a floating NSWindow running lazygit in the active worktree directory.
/// The window is created fresh on each open and destroyed when lazygit exits or
/// the user closes the window manually.
@MainActor
final class LazygitWindow: NSObject, NSWindowDelegate, ObservableObject {
    private var window: NSWindow?
    private var viewState: TerminalViewState?

    func open(workingDirectory: String) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // Run lazygit via the user's login shell so Homebrew/nvm/etc. PATH entries are available.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let state = TerminalViewState(
            terminalConfiguration: TerminalConfiguration {
                $0.withFontSize(13)
                $0.withCursorStyleBlink(true)
                $0.withCustom("command", "\(shell) -l -c lazygit")
            }
        )
        state.configuration = TerminalSurfaceOptions(backend: .exec, workingDirectory: workingDirectory)
        state.onClose = { [weak self] _ in
            Task { @MainActor [weak self] in self?.window?.close() }
        }

        let termView = AppTerminalView(frame: .zero)
        termView.delegate = state
        termView.configuration = state.configuration
        termView.controller = state.controller

        let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let size = CGSize(width: screenFrame.width * 0.8, height: screenFrame.height * 0.8)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "lazygit"
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.contentView = termView
        win.delegate = self
        win.makeKeyAndOrderFront(nil)

        window = win
        viewState = state
    }

    func windowWillClose(_: Notification) {
        window = nil
        viewState = nil
    }
}

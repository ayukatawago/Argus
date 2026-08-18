import AppKit
import ArgusConfigKit
import GhosttyTerminal

extension Notification.Name {
    static let openPopupTerminal = Notification.Name("argus.openPopupTerminal")
    static let openNvim = Notification.Name("argus.openNvim")
    static let focusPaneLeft = Notification.Name("argus.focusPaneLeft")
    static let focusPaneRight = Notification.Name("argus.focusPaneRight")
    static let selectNextWorktree = Notification.Name("argus.selectNextWorktree")
    static let selectPreviousWorktree = Notification.Name("argus.selectPreviousWorktree")
    static let refreshWorkspace = Notification.Name("argus.refreshWorkspace")
    static let workspaceInteracted = Notification.Name("argus.workspaceInteracted")
    static let openMarkdownPreview = Notification.Name("argus.openMarkdownPreview")
    static let openSettings = Notification.Name("argus.openSettings")
    static let reloadAgentPane = Notification.Name("argus.reloadAgentPane")
    static let openDiffReview = Notification.Name("argus.openDiffReview")
    static let newTerminalTab = Notification.Name("argus.newTerminalTab")
    static let nextTerminalTab = Notification.Name("argus.nextTerminalTab")
    static let previousTerminalTab = Notification.Name("argus.previousTerminalTab")
    static let closeTerminalTab = Notification.Name("argus.closeTerminalTab")
    static let toggleAgentSplit = Notification.Name("argus.toggleAgentSplit")
    /// Posted by `AppDelegate` for a CLI-originated `argus://diff` request — carries
    /// `workspace`/`base`/`head` in `userInfo` and, unlike `openDiffReview`, is resolved without
    /// consulting `WorkspaceStore` (the path is taken as-is, whether or not it's a tracked
    /// workspace).
    static let openDiffReviewForPath = Notification.Name("argus.openDiffReviewForPath")
}

/// Manages a single floating NSWindow running a user-defined command in the active
/// worktree directory. The window is created fresh on each open and destroyed when
/// the command exits or the user closes the window manually.
@MainActor
final class PopupTerminalWindow: NSObject, NSWindowDelegate, ObservableObject {
    private var window: NSWindow?
    private var viewState: TerminalViewState?

    func open(workingDirectory: String, command: String, title: String, sizePercent: Int) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // Run the command via the user's login shell so Homebrew/nvm/etc. PATH entries are available.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let state = TerminalViewState(
            terminalConfiguration: TerminalConfiguration {
                $0.withFontSize(13)
                $0.withCursorStyleBlink(true)
                $0.withCustom("command", "\(shell) -l -c '\(command)'")
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
        let ratio = Double(min(max(sizePercent, 30), 100)) / 100
        let size = CGSize(width: screenFrame.width * ratio, height: screenFrame.height * ratio)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.contentView = termView
        win.delegate = self
        win.makeKeyAndOrderFront(nil)

        window = win
        viewState = state

        // viewDidMoveToWindow fires when contentView is set, before makeKeyAndOrderFront,
        // so the window's effectiveAppearance may not yet match the system appearance.
        // Re-sync the color scheme on the next run loop tick once the window is settled.
        DispatchQueue.main.async { [weak self] in
            guard let win = self?.window, let state = self?.viewState else { return }
            let isDark = win.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            state.adopt(terminalColorScheme: isDark ? .dark : .light)
        }
    }

    func windowWillClose(_: Notification) {
        window = nil
        viewState = nil
    }
}

/// Owns one PopupTerminalWindow per configured shortcut so multiple popups can be
/// open at the same time without stomping on each other.
@MainActor
final class PopupTerminalManager: ObservableObject {
    private var windows: [String: PopupTerminalWindow] = [:]

    func open(_ shortcut: ArgusConfig.PopupShortcut, workingDirectory: String) {
        let window = windows[shortcut.id] ?? PopupTerminalWindow()
        windows[shortcut.id] = window
        window.open(
            workingDirectory: workingDirectory,
            command: shortcut.command,
            title: shortcut.name,
            sizePercent: shortcut.sizePercent
        )
    }
}

import AppKit
import ArgusSupport
import GhosttyTerminal

/// Manages a floating NSWindow running nvim in the active worktree directory.
/// The nvim session is backed by a named tmux session (argus-n-*) so it persists
/// when the popup is closed — reopening reattaches to the same session.
@MainActor
final class NvimWindow: NSObject, NSWindowDelegate, ObservableObject {
    private var window: NSWindow?
    private var viewState: TerminalViewState?
    private var cmdQMonitor: Any?

    func open(workingDirectory: String) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let session = WorktreePane.sessionName("n", path: workingDirectory)
        let command = TmuxCommand.attachOrCreate(
            tmux: Tmux.executable, session: session, command: [shell, "-l", "-c", "nvim"])
        let state = TerminalViewState(
            terminalConfiguration: TerminalConfiguration {
                $0.withFontSize(13)
                $0.withCursorStyleBlink(true)
                $0.withCustom("command", command)
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

        let screenFrame = NSScreen.popupVisibleFrame
        let size = CGSize(width: screenFrame.width * 0.8, height: screenFrame.height * 0.8)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "nvim"
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

    func windowDidBecomeKey(_: Notification) {
        cmdQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "h" {
                self?.window?.close()
                return nil
            }
            return event
        }
    }

    func windowDidResignKey(_: Notification) {
        removeCmdQMonitor()
    }

    func windowWillClose(_: Notification) {
        removeCmdQMonitor()
        window = nil
        viewState = nil
    }

    private func removeCmdQMonitor() {
        if let monitor = cmdQMonitor { NSEvent.removeMonitor(monitor) }
        cmdQMonitor = nil
    }
}

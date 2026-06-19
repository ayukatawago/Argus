import AppKit
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
        let command =
            "tmux new-session -A -s \(session) \(shell) -l -c 'nvim'"
            + " \\; set -s extended-keys on"
            + " \\; set-option -t \(session) status off"
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
        win.title = "nvim"
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.contentView = termView
        win.delegate = self
        win.makeKeyAndOrderFront(nil)

        window = win
        viewState = state
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

import AppKit
import GhosttyTerminal

/// Owns the terminal stack for one worktree using ghostty's native exec backend.
/// ghostty spawns and manages the shell process internally; we just set the
/// working directory and let the library own the PTY lifecycle.
@MainActor
final class WorktreePane {
    let terminalView: AppTerminalView
    private let viewState: TerminalViewState

    init(workingDirectory: String) {
        let stateInstance = TerminalViewState(
            terminalConfiguration: TerminalConfiguration {
                $0.withFontSize(13)
                $0.withCursorStyleBlink(true)
            }
        )
        stateInstance.configuration = TerminalSurfaceOptions(
            backend: .exec,
            workingDirectory: workingDirectory
        )

        let viewInstance = AppTerminalView(frame: .zero)
        viewInstance.delegate = stateInstance
        viewInstance.configuration = stateInstance.configuration
        viewInstance.controller = stateInstance.controller

        self.viewState = stateInstance
        self.terminalView = viewInstance
    }
}

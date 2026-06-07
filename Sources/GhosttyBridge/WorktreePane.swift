import AppKit
import GhosttyTerminal

/// Owns the terminal stack for one worktree — a shell pane on the left and a
/// Claude Code pane on the right. ghostty spawns and manages both shell processes
/// internally; we just set the working directory and let the library own the PTY lifecycle.
@MainActor
final class WorktreePane {
    let shellView: AppTerminalView
    let agentView: AppTerminalView
    private let shellState: TerminalViewState
    private let agentState: TerminalViewState

    init(workingDirectory: String) {
        let surfaceOptions = TerminalSurfaceOptions(backend: .exec, workingDirectory: workingDirectory)
        // Run claude via the login shell so Homebrew/nvm/etc. PATH entries are available.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let agentCommand = "\(shell) -l -c 'claude --continue || exec \(shell) -l'"

        shellState = Self.makeState()
        shellState.configuration = surfaceOptions
        shellView = Self.makeView(state: shellState)

        agentState = Self.makeState(command: agentCommand)
        agentState.configuration = surfaceOptions
        agentView = Self.makeView(state: agentState)
    }

    private static func makeState(command: String? = nil) -> TerminalViewState {
        let state = TerminalViewState(
            terminalConfiguration: TerminalConfiguration {
                $0.withFontSize(13)
                $0.withCursorStyleBlink(true)
                if let command { $0.withCustom("command", command) }
            }
        )
        return state
    }

    private static func makeView(state: TerminalViewState) -> AppTerminalView {
        let view = AppTerminalView(frame: .zero)
        view.delegate = state
        view.configuration = state.configuration
        view.controller = state.controller
        return view
    }
}

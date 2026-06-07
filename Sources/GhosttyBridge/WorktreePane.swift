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

        shellState = Self.makeState(workingDirectory: workingDirectory)
        shellState.configuration = surfaceOptions
        shellView = Self.makeView(state: shellState)

        agentState = Self.makeState(workingDirectory: workingDirectory, command: "claude --continue")
        agentState.configuration = surfaceOptions
        agentView = Self.makeView(state: agentState)
    }

    private static func makeState(workingDirectory: String, command: String? = nil) -> TerminalViewState {
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

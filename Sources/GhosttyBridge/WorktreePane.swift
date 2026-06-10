import AppKit
import GhosttyTerminal

/// Owns the terminal stack for one worktree — a shell pane on the left and a
/// Claude Code pane on the right. Both sessions are backed by named tmux sessions so
/// they persist across worktree release and can be shared with canvas card views.
@MainActor
final class WorktreePane {
    let shellView: AppTerminalView
    let agentView: AppTerminalView
    private let shellState: TerminalViewState
    private let agentState: TerminalViewState

    init(workingDirectory: String) {
        let surfaceOptions = TerminalSurfaceOptions(backend: .exec, workingDirectory: workingDirectory)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellSession = Self.sessionName("s", path: workingDirectory)
        let agentSession = Self.sessionName("a", path: workingDirectory)

        let shellCommand = "tmux new-session -A -s \(shellSession)"
        let claudeCmd = "claude --continue || exec \(shell) -l"
        let agentCommand = "tmux new-session -A -s \(agentSession) \(shell) -l -c '\(claudeCmd)'"

        shellState = Self.makeState(command: shellCommand)
        shellState.configuration = surfaceOptions
        shellView = Self.makeView(state: shellState)

        agentState = Self.makeState(command: agentCommand)
        agentState.configuration = surfaceOptions
        agentView = Self.makeView(state: agentState)
    }

    /// Derives a stable tmux session name from a worktree path.
    /// Example: "kotty-a-my-feature-a3f91c"
    ///
    /// The 6-hex-char suffix is FNV-1a over the full path, which is deterministic
    /// across process launches (unlike Swift's randomised hashValue).
    static func sessionName(_ type: String, path: String) -> String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        let hash = String(format: "%06x", fnv1a(path) & 0x00FF_FFFF)
        let safe = last.prefix(20).replacingOccurrences(
            of: #"[^a-zA-Z0-9_-]"#, with: "-", options: .regularExpression)
        return "kotty-\(type)-\(safe)-\(hash)"
    }

    /// FNV-1a 32-bit hash — fast, deterministic, no seed randomisation.
    private static func fnv1a(_ string: String) -> UInt32 {
        string.utf8.reduce(into: UInt32(2_166_136_261)) { hash, byte in
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
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

    static func makeView(state: TerminalViewState) -> AppTerminalView {
        let view = AppTerminalView(frame: .zero)
        view.delegate = state
        view.configuration = state.configuration
        view.controller = state.controller
        return view
    }
}

import AppKit
import ArgusConfigKit
import ArgusSupport
import GhosttyTerminal

/// The terminal role a pane serves within a worktree.
enum PaneRole {
    case shell
    case claude
    case codex
}

/// Owns the terminal stack for one worktree — a shell pane (always eager) and
/// optional agent panes (created lazily on first request). All sessions are
/// backed by named tmux sessions so they persist across worktree release and
/// can be shared with canvas card views.
@MainActor
final class WorktreePane {
    let workingDirectory: String
    private var views: [PaneRole: AppTerminalView] = [:]
    private var states: [PaneRole: TerminalViewState] = [:]

    /// Convenience accessor for the shell terminal (always pre-built).
    var shellView: AppTerminalView { view(for: .shell) }

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        // Eagerly create the shell pane so it is ready immediately.
        _ = view(for: .shell)
    }

    /// Returns the terminal view for `role`, creating it lazily on first call.
    func view(for role: PaneRole) -> AppTerminalView {
        if let existing = views[role] { return existing }
        let surfaceOptions = TerminalSurfaceOptions(backend: .exec, workingDirectory: workingDirectory)
        let shell = LoginShell.current
        let session = sessionName(for: role)
        let tmux = Self.tmuxExecutable
        let command: String
        let envPreamble = Self.envExportPreamble()
        switch role {
        case .shell:
            command =
                "\(tmux) new-session -A -s \(session) '\(envPreamble)exec \(shell) -l'"
                + " \\; set -s extended-keys on"
                + " \\; set-option -t \(session) status off"

        case .claude:
            let cmd = "\(envPreamble)\(ArgusConfigStore.shared.config.claudeCommand) || exec \(shell) -l"
            command =
                "\(tmux) new-session -A -s \(session) \(shell) -l -c '\(cmd)'"
                + " \\; set -s extended-keys on"
                + " \\; set-option -t \(session) status off"

        case .codex:
            let cmd = "\(envPreamble)\(ArgusConfigStore.shared.config.codexCommand) || exec \(shell) -l"
            command =
                "\(tmux) new-session -A -s \(session) \(shell) -l -c '\(cmd)'"
                + " \\; set -s extended-keys on"
                + " \\; set-option -t \(session) status off"
        }
        let state = Self.makeState(command: command)
        state.configuration = surfaceOptions
        let terminalView = Self.makeView(state: state, sessionName: session)
        states[role] = state
        views[role] = terminalView
        return terminalView
    }

    /// Returns the stable tmux session name for `role` in this worktree.
    func sessionName(for role: PaneRole) -> String {
        let type: String
        switch role {
        case .shell: type = "s"
        case .claude: type = "a"
        case .codex: type = "x"
        }
        return Self.sessionName(type, path: workingDirectory)
    }

    /// Derives a stable tmux session name from a worktree path.
    /// Example: "argus-a-my-feature-a3f91c"
    ///
    /// The 6-hex-char suffix is FNV-1a over the full path, which is deterministic
    /// across process launches (unlike Swift's randomised hashValue).
    static func sessionName(_ type: String, path: String) -> String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        let hash = String(format: "%06x", fnv1a(path) & 0x00FF_FFFF)
        let safe = last.prefix(20).replacingOccurrences(
            of: #"[^a-zA-Z0-9_-]"#, with: "-", options: .regularExpression)
        return "argus-\(type)-\(safe)-\(hash)"
    }

    // Produces "export KEY="value"; " for each configured env var.
    // Values are double-quote escaped so they survive the shell layer tmux invokes.
    // Changes take effect only when new tmux sessions are created (reload with leader+a).
    static func envExportPreamble() -> String {
        let vars = ArgusConfigStore.shared.config.environmentVariables
        guard !vars.isEmpty else { return "" }
        return vars.sorted(by: { $0.key < $1.key }).map { key, value in
            let escaped =
                value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "`", with: "\\`")
            return "export \(key)=\"\(escaped)\""
        }.joined(separator: "; ") + "; "
    }

    static var tmuxExecutable: String {
        let candidates = [
            ProcessInfo.processInfo.environment["ARGUS_TMUX"],
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "tmux"
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

    static func makeView(state: TerminalViewState, sessionName: String) -> AppTerminalView {
        let view = ArgusTerminalView(frame: .zero)
        view.sessionName = sessionName
        view.delegate = state
        view.configuration = state.configuration
        view.controller = state.controller
        return view
    }
}

import AppKit
import ArgusConfigKit
import ArgusSupport
import GhosttyTerminal

/// Owns the terminal stack for one worktree — a shell pane (always eager) and
/// optional agent panes (created lazily on first request). All sessions are
/// backed by named tmux sessions so they persist across worktree release.
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
        let envPreamble = Self.envExportPreamble()
        let program: [String]
        if let agent = role.agent {
            let launch = ArgusConfigStore.shared.config.launchCommand(for: agent)
            program = [shell, "-l", "-c", "\(envPreamble)\(launch) || exec \(ShellQuote.quote(shell)) -l"]
        } else {
            program = ["\(envPreamble)exec \(ShellQuote.quote(shell)) -l"]
        }
        let command = TmuxCommand.attachOrCreate(tmux: Tmux.executable, session: session, command: program)
        let state = Self.makeState(command: command)
        state.configuration = surfaceOptions
        let terminalView = Self.makeView(state: state, sessionName: session)
        states[role] = state
        views[role] = terminalView
        return terminalView
    }

    /// Drops the cached view/state for `role` so a later `view(for:)` call builds a fresh surface
    /// against a fresh tmux session, picking up the current launch command / environment
    /// variables. Used when an agent tab is closed — its tmux session is killed separately by the
    /// caller. `.shell` is never discarded; the shell pane always survives worktree pane teardown.
    func discardView(for role: PaneRole) {
        guard role != .shell else { return }
        views.removeValue(forKey: role)
        states.removeValue(forKey: role)
    }

    /// Returns the stable tmux session name for `role` in this worktree.
    func sessionName(for role: PaneRole) -> String {
        Self.sessionName(for: role, path: workingDirectory)
    }

    /// Derives a stable tmux session name from a worktree path. See TmuxSessionName for details.
    static func sessionName(_ type: String, path: String) -> String {
        TmuxSessionName.make(type: type, path: path)
    }

    /// Derives a stable tmux session name for `role` at `path`. See TmuxSessionName for details.
    static func sessionName(for role: PaneRole, path: String) -> String {
        sessionName(role.tmuxSessionType, path: path)
    }

    // Changes take effect only when new tmux sessions are created (reload with leader+a).
    static func envExportPreamble() -> String {
        EnvExportPreamble.make(from: ArgusConfigStore.shared.config.environmentVariables)
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

    private static func makeView(state: TerminalViewState, sessionName: String) -> AppTerminalView {
        let view = ArgusTerminalView(frame: .zero)
        view.sessionName = sessionName
        view.delegate = state
        view.configuration = state.configuration
        view.controller = state.controller
        return view
    }
}

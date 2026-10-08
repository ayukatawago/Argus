import Foundation

/// Pure builders for the tmux invocations Argus issues, plus tmux binary discovery. Kept free of
/// process spawning so the exact argv / command line is unit-testable; `App/` supplies the runner.
public enum TmuxCommand {
    /// Install locations probed in order, after an `ARGUS_TMUX` override.
    public static let executableCandidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    /// The tmux binary to run: the `ARGUS_TMUX` override if it is executable, else the first
    /// executable known install location, else the bare name `tmux` (resolved via `PATH`).
    ///
    /// A single resolution shared by every call site — terminal launch, polling, key bindings and
    /// Cmd+click URL capture previously each carried their own list, and the click path ignored the
    /// override entirely.
    public static func executablePath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        let candidates = [environment["ARGUS_TMUX"]].compactMap { $0 } + executableCandidates
        return candidates.first(where: isExecutable) ?? "tmux"
    }

    /// The command line a terminal surface runs to attach to `session`, creating it first when it
    /// doesn't exist (`new-session -A`), with extended keys on and the status bar hidden.
    ///
    /// `command` is the program tmux starts in a newly created session, given as separate words;
    /// each is quoted, so a value containing spaces, quotes or `$` reaches tmux exactly as written.
    /// Ignored by tmux when attaching to an existing session.
    public static func attachOrCreate(tmux: String, session: String, command: [String]) -> String {
        let create = ["new-session", "-A", "-s", session] + command
        return ShellQuote.join([tmux] + create)
            + " \\; set -s extended-keys on"
            + " \\; set-option -t \(ShellQuote.quote(session)) status off"
    }

    // MARK: - argv builders (arguments after the tmux executable)

    public static func killSession(_ session: String) -> [String] {
        ["kill-session", "-t", session]
    }

    public static func selectWindow(session: String, index: Int) -> [String] {
        ["select-window", "-t", "\(session):\(index)"]
    }

    public static func killWindow(session: String, index: Int) -> [String] {
        ["kill-window", "-t", "\(session):\(index)"]
    }

    /// A new window after the last one, started in `directory` and running `shellCommand`.
    public static func newWindow(session: String, directory: String, shellCommand: String) -> [String] {
        ["new-window", "-a", "-t", "\(session):{end}", "-c", directory, shellCommand]
    }

    public static func listWindows(session: String, format: String) -> [String] {
        ["list-windows", "-t", session, "-F", format]
    }

    /// `direction` is tmux's own flag: `-L`, `-R`, `-U` or `-D`.
    public static func selectPane(session: String, direction: String) -> [String] {
        ["select-pane", "-t", session, direction]
    }

    public static func listAllPanes(format: String) -> [String] {
        ["list-panes", "-a", "-F", format]
    }
}

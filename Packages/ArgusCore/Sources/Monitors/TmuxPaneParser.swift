import Foundation

/// Parses `tmux list-panes -a` output to determine which sessions have a foreground command
/// running, for the shell-busy sidebar indicator (the non-fish fallback path).
public enum TmuxPaneParser {
    /// tmux pane commands considered "just an idle shell prompt", not a foreground command.
    public static let shellNames: Set<String> = [
        "bash", "zsh", "fish", "sh", "dash", "ksh", "tcsh", "csh",
    ]

    /// Parses `tmux list-panes -a -F "#{session_name}|#{pane_current_command}"` output into a
    /// session name -> current command dictionary. Lines that don't match the expected
    /// `name|command` shape are skipped. A session with more than one pane (multiple tmux
    /// windows, e.g. the terminal tab bar, or a split) contributes more than one line for the
    /// same key — this keeps only the last one, which is why `busySessions` is built on
    /// `parseSessionCommandLists` instead.
    public static func parseSessionCommands(from output: String) -> [String: String] {
        var sessionToCommand: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            if parts.count == 2 {
                sessionToCommand[String(parts[0])] = String(parts[1])
            }
        }
        return sessionToCommand
    }

    /// Same parse as `parseSessionCommands`, but keeps every pane's command per session instead
    /// of collapsing to the last one — needed once a session can have more than one window/pane.
    public static func parseSessionCommandLists(from output: String) -> [String: [String]] {
        var sessionToCommands: [String: [String]] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            if parts.count == 2 {
                sessionToCommands[String(parts[0]), default: []].append(String(parts[1]))
            }
        }
        return sessionToCommands
    }

    /// Returns the subset of `activeSessions` with at least one pane whose current command isn't
    /// a known shell name — i.e. a foreground command is running somewhere in the session, not
    /// just sitting at a prompt. A session absent from the parsed output entirely (no live tmux
    /// pane) is not considered busy.
    public static func busySessions(from output: String, activeSessions: Set<String>) -> Set<String> {
        let sessionToCommands = parseSessionCommandLists(from: output)
        return activeSessions.filter { session in
            guard let commands = sessionToCommands[session] else { return false }
            return commands.contains { !shellNames.contains($0) }
        }
    }
}

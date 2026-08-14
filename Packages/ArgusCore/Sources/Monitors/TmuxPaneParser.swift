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
    /// `name|command` shape are skipped.
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

    /// Returns the subset of `activeSessions` whose current tmux command isn't a known shell name
    /// — i.e. a foreground command is running, not just sitting at a prompt. A session absent
    /// from the parsed output entirely (no live tmux pane) is not considered busy.
    public static func busySessions(from output: String, activeSessions: Set<String>) -> Set<String> {
        let sessionToCommand = parseSessionCommands(from: output)
        return activeSessions.filter { session in
            guard let command = sessionToCommand[session] else { return false }
            return !shellNames.contains(command)
        }
    }
}

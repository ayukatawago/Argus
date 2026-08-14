import Foundation

/// Builds a shell command preamble that exports the configured environment variables before a
/// tmux session's command runs.
public enum EnvExportPreamble {
    /// Produces `"export KEY=\"value\"; "` for each variable, sorted by key for a stable output.
    /// Values are double-quote escaped so they survive the shell layer tmux invokes. Returns ""
    /// for an empty dictionary (no trailing "; " with nothing before it).
    public static func make(from environmentVariables: [String: String]) -> String {
        guard !environmentVariables.isEmpty else { return "" }
        return environmentVariables.sorted(by: { $0.key < $1.key }).map { key, value in
            let escaped =
                value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "`", with: "\\`")
            return "export \(key)=\"\(escaped)\""
        }.joined(separator: "; ") + "; "
    }
}

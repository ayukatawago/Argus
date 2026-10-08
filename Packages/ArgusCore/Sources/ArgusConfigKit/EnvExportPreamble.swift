import Foundation

/// Builds a shell command preamble that exports the configured environment variables before a
/// tmux session's command runs.
public enum EnvExportPreamble {
    /// Produces `"export KEY=\"value\"; "` for each variable, sorted by key for a stable output.
    /// Values are double-quote escaped so they survive the shell layer tmux invokes. Returns ""
    /// for an empty dictionary (no trailing "; " with nothing before it).
    ///
    /// A key that isn't a valid shell identifier is skipped: it is interpolated unquoted into
    /// `export KEY=…`, so a key like `A; rm -rf ~` or `A B` would inject a command or break the line.
    public static func make(from environmentVariables: [String: String]) -> String {
        let valid = environmentVariables.filter { isValidName($0.key) }
        guard !valid.isEmpty else { return "" }
        return valid.sorted(by: { $0.key < $1.key }).map { key, value in
            let escaped =
                value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "`", with: "\\`")
            return "export \(key)=\"\(escaped)\""
        }.joined(separator: "; ") + "; "
    }

    /// `[A-Za-z_][A-Za-z0-9_]*`
    static func isValidName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || isASCIILetter(first) else { return false }
        return name.unicodeScalars.allSatisfy { $0 == "_" || isASCIILetter($0) || ("0"..."9").contains($0) }
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }
}

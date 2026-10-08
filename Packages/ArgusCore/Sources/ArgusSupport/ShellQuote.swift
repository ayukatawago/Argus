import Foundation

/// POSIX single-quote escaping for building shell command lines.
///
/// A command line handed to a terminal surface or to `tmux new-session` is parsed by a shell, so
/// any value interpolated into it — a configured launch command, a popup command, an environment
/// value, a path — has to survive that parse. Wrapping a value in `'…'` without escaping an embedded
/// `'` (the previous approach) both breaks the command and lets the value inject its own.
public enum ShellQuote {
    /// Characters that never need quoting in a POSIX shell word.
    private static let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-")

    /// Returns `value` as a single shell word: unchanged when it consists only of safe characters
    /// (so ordinary paths and flags stay readable), otherwise wrapped in single quotes with each
    /// embedded `'` written as `'\''`. The empty string becomes `''`.
    public static func quote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        if value.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Quotes each word and joins them with single spaces.
    public static func join(_ words: [String]) -> String {
        words.map(quote).joined(separator: " ")
    }
}

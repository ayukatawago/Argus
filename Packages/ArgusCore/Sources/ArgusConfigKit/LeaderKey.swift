import Foundation

/// A parsed leader-key chord: the modifiers that must be held plus the trailing character,
/// independent of any UI framework's own modifier-flags type.
public struct LeaderChord: Equatable, Sendable {
    public enum Modifier: Sendable {
        case control
        case command
        case option
        case shift
    }

    public let modifiers: Set<Modifier>
    public let character: String

    public init(modifiers: Set<Modifier>, character: String) {
        self.modifiers = modifiers
        self.character = character
    }
}

/// Parses the `leaderKey` config string (e.g. `"ctrl+b"`, `"cmd+shift+p"`).
public enum LeaderKey {
    /// Splits on `+`; the last component is the character, everything before it is a modifier
    /// name. Unrecognized modifier names (typos, etc.) are silently ignored rather than failing
    /// the whole parse — matching the original AppDelegate.parseLeaderKey behavior. `split`
    /// drops empty components by default, so a trailing `+` doesn't produce an empty character
    /// (`"b+"` parses the same as `"b"`); returns `nil` only when there's no non-empty component
    /// at all (`""`, `"+"`, `"++"`, ...).
    ///
    /// A `+` *key* is written as a doubled trailing plus after at least one modifier (`"ctrl++"` is
    /// control and the `+` character); with no modifier before it (`"++"`) there is nothing to bind
    /// and it stays `nil`.
    public static func parse(_ key: String) -> LeaderChord? {
        let lowered = key.lowercased()
        var parts = lowered.split(separator: "+").map(String.init)
        if lowered.hasSuffix("++"), !parts.isEmpty { parts.append("+") }
        guard let char = parts.last, !char.isEmpty else { return nil }
        var modifiers: Set<LeaderChord.Modifier> = []
        for part in parts.dropLast() {
            switch part {
            case "ctrl": modifiers.insert(.control)
            case "cmd", "command": modifiers.insert(.command)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default: break
            }
        }
        return LeaderChord(modifiers: modifiers, character: char)
    }
}

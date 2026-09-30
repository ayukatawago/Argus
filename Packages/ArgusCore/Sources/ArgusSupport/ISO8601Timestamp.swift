import Foundation

/// Parses an ISO-8601 timestamp string that may or may not carry fractional seconds — the shape
/// both Claude Code's transcript `timestamp` field and Codex's rollout `timestamp` field use.
/// Shared so `ClaudeTranscriptParser` and `CodexUsageParser` don't each carry their own pair of
/// `Date.ISO8601FormatStyle` statics.
public enum ISO8601Timestamp {
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()

    public static func parse(_ value: String) -> Date? {
        (try? withFraction.parse(value)) ?? (try? withoutFraction.parse(value))
    }
}

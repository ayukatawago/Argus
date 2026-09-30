import Foundation

/// Pure path math for Codex's `~/.codex/sessions/<year>/<month>/<day>/` layout.
///
/// A separate, parameterized version of the day-directory math `CodexSessionWatcher` already
/// does for its own (hardcoded `0...1` day, state-inference) purposes: that one is `private` and
/// bakes the lookback window into its loop, so it can't be reused here where the usage scan needs
/// a much wider window — a session resumed days after creation keeps appending to its *original*
/// day's file indefinitely (see `CodexSessionWatcher.scanOnce`'s own comment on this), so a usage
/// total that only looked at today's directory would silently miss that session's tokens.
public enum CodexRolloutLocator {
    /// Directories for `now` and the `days - 1` days before it, oldest first. Does not touch the
    /// filesystem — callers list each directory's contents themselves, so this stays testable
    /// without a real `~/.codex`.
    public static func dayDirectories(
        base: URL, days: Int, now: Date, calendar: Calendar
    ) -> [URL] {
        guard days > 0 else { return [] }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let comps = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = comps.year, let month = comps.month, let dayOfMonth = comps.day else { return nil }
            return
                base
                .appendingPathComponent(String(format: "%04d", year))
                .appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", dayOfMonth))
        }
    }
}

import Foundation

/// Sets aside an unreadable user file before the app falls back to defaults.
///
/// Every config store here "returns defaults when the file fails to decode", and the very next
/// `save()` then overwrites it — so one hand-edit typo (a trailing comma, a `//` comment) would
/// silently destroy the user's data. Copying the file aside first keeps it recoverable.
public enum CorruptFileBackup {
    /// Copies the non-empty file at `url` to `<name>.corrupt-<unix seconds>` beside it. Returns the
    /// backup's URL, or `nil` when there was nothing to preserve (missing/empty file), an identical
    /// backup already exists (the same bad file loaded on several launches), or the copy failed —
    /// preserving is best-effort and must never block the app from starting.
    @discardableResult
    public static func preserve(_ url: URL, now: Date = Date(), fileManager: FileManager = .default) -> URL? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".corrupt-"
        let siblings = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in siblings where name.hasPrefix(prefix) {
            if (try? Data(contentsOf: directory.appendingPathComponent(name))) == data { return nil }
        }
        let backup = directory.appendingPathComponent(prefix + String(Int(now.timeIntervalSince1970)))
        do {
            try data.write(to: backup, options: .atomic)
            return backup
        } catch {
            return nil
        }
    }
}

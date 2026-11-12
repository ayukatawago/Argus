import ArgusSupport
import Foundation

/// hidden-prs.json read/write against an injectable URL, so persistence is testable without
/// touching the real `~/Library/Application Support/argus/hidden-prs.json`.
public enum PRHiddenFile {
    private struct Entry: Codable {
        let id: Int
        let updatedAt: String?
    }

    private struct Payload: Codable {
        let hidden: [Entry]
    }

    /// The pre-snooze format: ids only, no `updated_at` baseline.
    private struct LegacyPayload: Decodable {
        let hiddenPRIDs: [Int]
    }

    /// Loads the hidden PRs (id → `updated_at` when hidden) at `url`, falling back to empty if the
    /// file is missing or fails to decode. A legacy ids-only file loads with `nil` baselines.
    public static func load(from url: URL) -> [Int: String?] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(Payload.self, from: data) {
            return Dictionary(payload.hidden.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { first, _ in first })
        }
        if let legacy = try? decoder.decode(LegacyPayload.self, from: data) {
            return Dictionary(legacy.hiddenPRIDs.map { ($0, String?.none) }, uniquingKeysWith: { first, _ in first })
        }
        CorruptFileBackup.preserve(url)
        return [:]
    }

    /// Writes `entries` to `url`, creating intermediate directories as needed. Best-effort:
    /// silently no-ops on failure, matching `WorkspaceConfigFile`'s behavior.
    public static func save(_ entries: [Int: String?], to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = Payload(hidden: entries.keys.sorted().map { Entry(id: $0, updatedAt: entries[$0] ?? nil) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try? encoder.encode(payload)
        try? data?.write(to: url, options: .atomic)
    }
}

import ArgusSupport
import Foundation

/// hidden-prs.json read/write against an injectable URL, so persistence is testable without
/// touching the real `~/Library/Application Support/argus/hidden-prs.json`.
public enum PRHiddenFile {
    /// Loads the hidden PR ids at `url`, falling back to an empty set if the file is missing or
    /// fails to decode.
    public static func load(from url: URL) -> Set<Int> {
        struct Payload: Decodable {
            let hiddenPRIDs: [Int]
        }
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            CorruptFileBackup.preserve(url)
            return []
        }
        return Set(payload.hiddenPRIDs)
    }

    /// Writes `ids` to `url`, creating intermediate directories as needed. Best-effort:
    /// silently no-ops on failure, matching `WorkspaceConfigFile`'s behavior.
    public static func save(_ ids: Set<Int>, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        struct Encoded: Encodable {
            let hiddenPRIDs: [Int]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try? encoder.encode(Encoded(hiddenPRIDs: ids.sorted()))
        try? data?.write(to: url, options: .atomic)
    }
}

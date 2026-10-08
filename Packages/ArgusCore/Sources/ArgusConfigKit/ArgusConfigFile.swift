import ArgusSupport
import Foundation

/// argus.json read/write against an injectable URL, so config persistence is testable without
/// touching the real `~/.config/argus/argus.json`.
public enum ArgusConfigFile {
    /// Loads the config at `url`, falling back to `ArgusConfig()` (every field default) if the
    /// file is missing or fails to decode. An existing but undecodable file is copied aside
    /// (`CorruptFileBackup`) first, so the next `save()` can't destroy the user's hand-edits.
    public static func load(from url: URL) -> ArgusConfig {
        guard let data = try? Data(contentsOf: url) else { return ArgusConfig() }
        guard let decoded = try? JSONDecoder().decode(ArgusConfig.self, from: data) else {
            CorruptFileBackup.preserve(url)
            return ArgusConfig()
        }
        return decoded
    }

    /// Writes `config` to `url` as pretty-printed, sorted-key JSON, creating intermediate
    /// directories as needed. Best-effort: silently no-ops on failure, matching the store's
    /// original behavior (a config write is never worth crashing or surfacing an error for).
    public static func save(_ config: ArgusConfig, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

import Foundation

/// The persisted state of WorkspaceStore: configured root folders, hidden worktree IDs, repos the
/// user removed from an auto-discovered root, the sidebar's drag-reorder, and which worktrees had
/// a live pane open (so relaunch can reattach them instead of only the last-selected one).
public struct WorkspaceConfig: Equatable, Sendable {
    public var roots: [String]
    public var hiddenWorktreeIDs: Set<String>
    public var excludedRepoPaths: Set<String>
    public var repoOrder: [String]
    public var openWorktreeIDs: Set<String>

    public init(
        roots: [String],
        hiddenWorktreeIDs: Set<String> = [],
        excludedRepoPaths: Set<String> = [],
        repoOrder: [String] = [],
        openWorktreeIDs: Set<String> = []
    ) {
        self.roots = roots
        self.hiddenWorktreeIDs = hiddenWorktreeIDs
        self.excludedRepoPaths = excludedRepoPaths
        self.repoOrder = repoOrder
        self.openWorktreeIDs = openWorktreeIDs
    }
}

/// workspaces.json read/write against an injectable URL, so persistence is testable without
/// touching the real `~/Library/Application Support/argus/workspaces.json`.
public enum WorkspaceConfigFile {
    /// Loads the config at `url`, falling back to `WorkspaceConfig(roots: defaultRoots)` (every
    /// other field empty) if the file is missing or fails to decode.
    public static func load(from url: URL, defaultRoots: [String]) -> WorkspaceConfig {
        struct Payload: Decodable {
            let roots: [String]
            let hiddenWorktreeIDs: [String]?
            let excludedRepoPaths: [String]?
            let repoOrder: [String]?
            let openWorktreeIDs: [String]?
        }
        guard let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return WorkspaceConfig(roots: defaultRoots)
        }
        return WorkspaceConfig(
            roots: payload.roots,
            hiddenWorktreeIDs: Set(payload.hiddenWorktreeIDs ?? []),
            excludedRepoPaths: Set(payload.excludedRepoPaths ?? []),
            repoOrder: payload.repoOrder ?? [],
            openWorktreeIDs: Set(payload.openWorktreeIDs ?? [])
        )
    }

    /// Writes `config` to `url`, creating intermediate directories as needed. Best-effort:
    /// silently no-ops on failure, matching the store's original behavior.
    public static func save(_ config: WorkspaceConfig, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        struct Encoded: Encodable {
            let roots: [String]
            let hiddenWorktreeIDs: [String]
            let excludedRepoPaths: [String]
            let repoOrder: [String]
            let openWorktreeIDs: [String]
        }
        let data = try? JSONEncoder().encode(
            Encoded(
                roots: config.roots,
                hiddenWorktreeIDs: Array(config.hiddenWorktreeIDs),
                excludedRepoPaths: Array(config.excludedRepoPaths),
                repoOrder: config.repoOrder,
                openWorktreeIDs: Array(config.openWorktreeIDs)
            ))
        try? data?.write(to: url)
    }
}

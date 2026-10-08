import ArgusSupport
import Foundation

public struct GitWorktree: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let branch: String?
    public let isMain: Bool

    public init(path: String, branch: String?, isMain: Bool) {
        self.path = path
        self.branch = branch
        self.isMain = isMain
    }
}

public struct GitRepo: Identifiable, Equatable, Sendable {
    public var id: String { mainPath }
    public let name: String
    public let mainPath: String
    public var worktrees: [GitWorktree]
    public var isGitRepo: Bool = true

    public init(name: String, mainPath: String, worktrees: [GitWorktree], isGitRepo: Bool = true) {
        self.name = name
        self.mainPath = mainPath
        self.worktrees = worktrees
        self.isGitRepo = isGitRepo
    }
}

@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public var repos: [GitRepo] = []
    @Published public var hiddenWorktreeIDs: Set<String> = []
    /// Worktrees that had a live pane open when the app last quit — read once on `load()` so
    /// `AppShellView` can reattach their tmux sessions in the background on relaunch, mirroring
    /// `PanePool.activeIDs` across the process boundary. Kept in sync via `setOpenWorktreeIDs`.
    @Published public private(set) var openWorktreeIDs: Set<String> = []
    public private(set) var roots: [String] = []
    private var excludedRepoPaths: Set<String> = []
    private var repoOrder: [String] = []
    private var scanner: WorkspaceScanner?
    /// The last successfully (or fallback-)resolved repo list per root, keyed by root path. Used
    /// to keep showing a root's repos when a scan of it can't be completed (see `refresh`).
    private var lastGoodReposByRoot: [String: [GitRepo]] = [:]
    private var scanTask: Task<Void, Never>?
    private var rescanRequested = false
    /// Injected so tests can drive `refresh()` against a fake without shelling out to git.
    private let worktreeLister: @Sendable (String, [GitWorktree]?) async -> [GitWorktree]

    public init(
        worktreeLister: @escaping @Sendable (String, [GitWorktree]?) async -> [GitWorktree] =
            WorkspaceStore.fetchWorktrees
    ) {
        self.worktreeLister = worktreeLister
    }

    public func load() {
        let stored = Self.loadConfig()
        roots = stored.roots
        hiddenWorktreeIDs = stored.hiddenWorktreeIDs
        excludedRepoPaths = stored.excludedRepoPaths
        repoOrder = stored.repoOrder
        openWorktreeIDs = stored.openWorktreeIDs
        startWatcher()
        requestRefresh()
    }

    /// Called whenever `PanePool.activeIDs` changes, so the set of open worktrees survives quit/relaunch.
    public func setOpenWorktreeIDs(_ ids: Set<String>) {
        guard openWorktreeIDs != ids else { return }
        openWorktreeIDs = ids
        saveConfig()
    }

    public func addRoot(_ path: String) {
        guard !roots.contains(path) else { return }
        roots.append(path)
        saveConfig()
        startWatcher()
        requestRefresh()
    }

    public func removeRoot(_ path: String) {
        roots.removeAll { $0 == path }
        saveConfig()
        startWatcher()
        requestRefresh()
    }

    public func removeRepo(mainPath: String) {
        if roots.contains(mainPath) {
            roots.removeAll { $0 == mainPath }
            startWatcher()
        } else {
            excludedRepoPaths.insert(mainPath)
        }
        saveConfig()
        requestRefresh()
    }

    // Internal (not private) so tests can seed scan configuration directly via @testable import,
    // without touching the real on-disk config (`saveConfig`) or starting a real FSEvents watcher
    // the way `load()`/`addRoot()` do.
    func configureForTesting(roots: [String], excluding: Set<String> = []) {
        self.roots = roots
        excludedRepoPaths = excluding
    }

    public func hideWorktree(id: String) {
        hiddenWorktreeIDs.insert(id)
        saveConfig()
    }

    /// Undoes `hideWorktree` — used when a worktree was hidden optimistically ahead of a removal
    /// that then failed.
    public func unhideWorktree(id: String) {
        guard hiddenWorktreeIDs.remove(id) != nil else { return }
        saveConfig()
    }

    public func unhideWorktrees(repoID: String) {
        guard let repo = repos.first(where: { $0.id == repoID }) else { return }
        repo.worktrees.forEach { hiddenWorktreeIDs.remove($0.id) }
        saveConfig()
    }

    /// The `mainPath` of the repo owning the worktree at `path`, or `nil` if untracked. See
    /// `RepoLookup`.
    public func repoMainPath(forWorktreePath path: String) -> String? {
        RepoLookup.mainPath(forWorktreePath: path, in: repos)
    }

    public func moveRepo(fromIndex: Int, toIndex: Int) {
        guard let order = RepoOrdering.move(fromIndex: fromIndex, toIndex: toIndex, in: repos) else { return }
        let snapshot = repos
        repoOrder = order
        repos = order.compactMap { path in snapshot.first(where: { $0.mainPath == path }) }
        saveConfig()
    }

    /// Coalesces bursts of refresh requests (FSEvents callbacks, the manual refresh binding) into a
    /// single scan at a time: a request that arrives while one is already running just flags
    /// another pass instead of starting a second, overlapping scan. Overlapping scans could
    /// otherwise interleave their `git` spawns and publish out of order — a slower, older scan
    /// landing after a newer one.
    public func requestRefresh() {
        rescanRequested = true
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { self.scanTask = nil }
            while self.rescanRequested {
                self.rescanRequested = false
                await self.refresh()
            }
        }
    }

    public func refresh() async {
        let currentRoots = roots
        let currentExcluded = excludedRepoPaths
        let previousWorktreesByPath = Dictionary(
            repos.map { ($0.mainPath, $0.worktrees) }, uniquingKeysWith: { first, _ in first })
        let previousReposByRoot = lastGoodReposByRoot
        let lister = worktreeLister

        let scannedByRoot = await Task.detached(priority: .userInitiated) { () async -> [(String, [GitRepo])] in
            var result: [(String, [GitRepo])] = []
            for root in currentRoots {
                let scanned = await RepoScanner.findRepos(
                    under: root,
                    excluding: currentExcluded,
                    worktreeLister: { path in await lister(path, previousWorktreesByPath[path]) }
                )
                if let scanned {
                    result.append((root, scanned))
                } else if let fallback = previousReposByRoot[root] {
                    // The listing failed transiently (permission blip, unavailable volume) — keep
                    // whatever this root last resolved to instead of dropping its repos.
                    result.append((root, fallback))
                }
            }
            return result
        }.value

        var newLastGoodReposByRoot: [String: [GitRepo]] = [:]
        var discovered: [GitRepo] = []
        for (root, repoList) in scannedByRoot {
            newLastGoodReposByRoot[root] = repoList
            discovered.append(contentsOf: repoList)
        }
        lastGoodReposByRoot = newLastGoodReposByRoot

        let ordered = applyOrder(discovered)
        if ordered != repos {
            repos = ordered
        }
    }

    private func applyOrder(_ discovered: [GitRepo]) -> [GitRepo] {
        RepoOrdering.apply(order: repoOrder, to: discovered)
    }

    private func startWatcher() {
        let watcher = WorkspaceScanner()
        watcher.onChange = { [weak self] in
            Task { @MainActor [weak self] in self?.requestRefresh() }
        }
        watcher.start(paths: roots)
        scanner = watcher
    }

    private nonisolated static var configURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("argus/workspaces.json")
    }

    private func saveConfig() {
        guard let url = Self.configURL else { return }
        let config = WorkspaceConfig(
            roots: roots,
            hiddenWorktreeIDs: hiddenWorktreeIDs,
            excludedRepoPaths: excludedRepoPaths,
            repoOrder: repoOrder,
            openWorktreeIDs: openWorktreeIDs
        )
        WorkspaceConfigFile.save(config, to: url)
    }

    private nonisolated static func loadConfig() -> WorkspaceConfig {
        guard let url = configURL else { return WorkspaceConfig(roots: defaultRoots()) }
        return WorkspaceConfigFile.load(from: url, defaultRoots: defaultRoots())
    }

    private nonisolated static func defaultRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let workspace = home + "/workspace"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: workspace, isDirectory: &isDir), isDir.boolValue {
            return [workspace]
        }
        return [home]
    }

    /// `fallback`, when present, is the repo's worktree list from the last successful scan. A
    /// failed or empty result falls back to it instead of collapsing the repo to a single
    /// synthetic main worktree — a transient `git` failure (spawn pressure from an overlapping
    /// scan, index-lock contention, ...) would otherwise make every linked worktree vanish from
    /// the sidebar until the next successful scan.
    public nonisolated static func fetchWorktrees(repoPath: String, fallback: [GitWorktree]?) async -> [GitWorktree] {
        let result = await ProcessRunner.run(
            "/usr/bin/git", ["-C", repoPath, "worktree", "list", "--porcelain"], timeout: 5)
        guard result.succeeded else {
            return fallback ?? [GitWorktree(path: repoPath, branch: nil, isMain: true)]
        }
        let parsed = WorktreeListParser.parse(result.standardOutput)
        return parsed.isEmpty ? (fallback ?? []) : parsed
    }
}

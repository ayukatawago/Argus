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

    public static func == (lhs: GitWorktree, rhs: GitWorktree) -> Bool { lhs.path == rhs.path }
    public func hash(into hasher: inout Hasher) { hasher.combine(path) }
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
    public private(set) var roots: [String] = []
    private var excludedRepoPaths: Set<String> = []
    private var repoOrder: [String] = []
    private var scanner: WorkspaceScanner?

    public init() {}

    public func load() {
        let stored = Self.loadConfig()
        roots = stored.roots
        hiddenWorktreeIDs = stored.hiddenWorktreeIDs
        excludedRepoPaths = stored.excludedRepoPaths
        repoOrder = stored.repoOrder
        startWatcher()
        Task { await refresh() }
    }

    public func addRoot(_ path: String) {
        guard !roots.contains(path) else { return }
        roots.append(path)
        saveConfig()
        startWatcher()
        Task { await refresh() }
    }

    public func removeRoot(_ path: String) {
        roots.removeAll { $0 == path }
        saveConfig()
        startWatcher()
        Task { await refresh() }
    }

    public func removeRepo(mainPath: String) {
        if roots.contains(mainPath) {
            roots.removeAll { $0 == mainPath }
            startWatcher()
        } else {
            excludedRepoPaths.insert(mainPath)
        }
        saveConfig()
        Task { await refresh() }
    }

    public func hideWorktree(id: String) {
        hiddenWorktreeIDs.insert(id)
        saveConfig()
    }

    public func unhideWorktrees(repoID: String) {
        guard let repo = repos.first(where: { $0.id == repoID }) else { return }
        repo.worktrees.forEach { hiddenWorktreeIDs.remove($0.id) }
        saveConfig()
    }

    public func moveRepo(fromIndex: Int, toIndex: Int) {
        guard let order = RepoOrdering.move(fromIndex: fromIndex, toIndex: toIndex, in: repos) else { return }
        let snapshot = repos
        repoOrder = order
        repos = order.compactMap { path in snapshot.first(where: { $0.mainPath == path }) }
        saveConfig()
    }

    public func refresh() async {
        let currentRoots = roots
        let currentExcluded = excludedRepoPaths
        let discovered = await Task.detached(priority: .userInitiated) { () async -> [GitRepo] in
            var result: [GitRepo] = []
            for root in currentRoots {
                result.append(
                    contentsOf: await RepoScanner.findRepos(
                        under: root, excluding: currentExcluded, worktreeLister: Self.fetchWorktrees))
            }
            return result
        }.value
        repos = applyOrder(discovered)
    }

    private func applyOrder(_ discovered: [GitRepo]) -> [GitRepo] {
        RepoOrdering.apply(order: repoOrder, to: discovered)
    }

    private func startWatcher() {
        let watcher = WorkspaceScanner()
        watcher.onChange = { [weak self] in
            Task { @MainActor [weak self] in await self?.refresh() }
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
            repoOrder: repoOrder
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

    private nonisolated static func fetchWorktrees(repoPath: String) async -> [GitWorktree] {
        let result = await ProcessRunner.run("/usr/bin/git", ["-C", repoPath, "worktree", "list", "--porcelain"])
        guard result.succeeded else {
            return [GitWorktree(path: repoPath, branch: nil, isMain: true)]
        }
        return WorktreeListParser.parse(result.standardOutput)
    }
}

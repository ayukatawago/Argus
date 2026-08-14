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
                result.append(contentsOf: await Self.findRepos(under: root, excluding: currentExcluded))
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

    private func saveConfig() {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { return }
        let dir = appSupport.appendingPathComponent("argus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        struct Config: Encodable {
            let roots: [String]
            let hiddenWorktreeIDs: [String]
            let excludedRepoPaths: [String]
            let repoOrder: [String]
        }
        let data = try? JSONEncoder().encode(
            Config(
                roots: roots,
                hiddenWorktreeIDs: Array(hiddenWorktreeIDs),
                excludedRepoPaths: Array(excludedRepoPaths),
                repoOrder: repoOrder
            ))
        try? data?.write(to: dir.appendingPathComponent("workspaces.json"))
    }

    private struct StoredConfig {
        let roots: [String]
        let hiddenWorktreeIDs: Set<String>
        let excludedRepoPaths: Set<String>
        let repoOrder: [String]
    }

    private nonisolated static func loadConfig() -> StoredConfig {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            return StoredConfig(roots: defaultRoots(), hiddenWorktreeIDs: [], excludedRepoPaths: [], repoOrder: [])
        }
        let configURL = appSupport.appendingPathComponent("argus/workspaces.json")
        struct Payload: Decodable {
            let roots: [String]
            let hiddenWorktreeIDs: [String]?
            let excludedRepoPaths: [String]?
            let repoOrder: [String]?
        }
        if let data = try? Data(contentsOf: configURL),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        {
            return StoredConfig(
                roots: payload.roots,
                hiddenWorktreeIDs: Set(payload.hiddenWorktreeIDs ?? []),
                excludedRepoPaths: Set(payload.excludedRepoPaths ?? []),
                repoOrder: payload.repoOrder ?? []
            )
        }
        return StoredConfig(roots: defaultRoots(), hiddenWorktreeIDs: [], excludedRepoPaths: [], repoOrder: [])
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

    private nonisolated static func findRepos(under root: String, excluding: Set<String>) async -> [GitRepo] {
        let files = FileManager.default

        var isGitDir: ObjCBool = false
        files.fileExists(atPath: root + "/.git", isDirectory: &isGitDir)
        if isGitDir.boolValue {
            guard !excluding.contains(root) else { return [] }
            let worktrees = await fetchWorktrees(repoPath: root)
            guard !worktrees.isEmpty else { return [] }
            let name = URL(fileURLWithPath: root).lastPathComponent
            return [GitRepo(name: name, mainPath: root, worktrees: worktrees)]
        }

        guard let entries = try? files.contentsOfDirectory(atPath: root) else { return [] }
        var found: [GitRepo] = []
        for name in entries.sorted() {
            let path = root + "/" + name
            guard !excluding.contains(path) else { continue }
            var isDir: ObjCBool = false
            files.fileExists(atPath: path + "/.git", isDirectory: &isDir)
            guard isDir.boolValue else { continue }
            let worktrees = await fetchWorktrees(repoPath: path)
            guard !worktrees.isEmpty else { continue }
            found.append(GitRepo(name: name, mainPath: path, worktrees: worktrees))
        }
        if found.isEmpty {
            guard !excluding.contains(root) else { return [] }
            let name = URL(fileURLWithPath: root).lastPathComponent
            let worktree = GitWorktree(path: root, branch: nil, isMain: true)
            return [GitRepo(name: name, mainPath: root, worktrees: [worktree], isGitRepo: false)]
        }
        return found
    }

    private nonisolated static func fetchWorktrees(repoPath: String) async -> [GitWorktree] {
        let result = await ProcessRunner.run("/usr/bin/git", ["-C", repoPath, "worktree", "list", "--porcelain"])
        guard result.succeeded else {
            return [GitWorktree(path: repoPath, branch: nil, isMain: true)]
        }
        return WorktreeListParser.parse(result.standardOutput)
    }
}

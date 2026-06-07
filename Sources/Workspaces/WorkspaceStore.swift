import Foundation

struct GitWorktree: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let branch: String?
    let isMain: Bool

    static func == (lhs: GitWorktree, rhs: GitWorktree) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

struct GitRepo: Identifiable {
    var id: String { mainPath }
    let name: String
    let mainPath: String
    var worktrees: [GitWorktree]
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var repos: [GitRepo] = []
    private(set) var roots: [String] = []
    private var scanner: WorkspaceScanner?

    func load() {
        roots = Self.loadRoots()
        let watcher = WorkspaceScanner()
        watcher.onChange = { [weak self] in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        watcher.start(paths: roots)
        scanner = watcher
        Task { await refresh() }
    }

    func refresh() async {
        let currentRoots = roots
        let discovered = await Task.detached(priority: .userInitiated) {
            currentRoots.flatMap { Self.findRepos(under: $0) }
        }.value
        repos = discovered
    }

    private nonisolated static func loadRoots() -> [String] {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return defaultRoots() }
        let configURL = appSupport.appendingPathComponent("kotty/workspaces.json")
        struct Config: Decodable { let roots: [String] }
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config.roots
        }
        return defaultRoots()
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

    private nonisolated static func findRepos(under root: String) -> [GitRepo] {
        let files = FileManager.default
        guard let entries = try? files.contentsOfDirectory(atPath: root) else { return [] }
        return entries.sorted().compactMap { name -> GitRepo? in
            let path = root + "/" + name
            var isDir: ObjCBool = false
            files.fileExists(atPath: path + "/.git", isDirectory: &isDir)
            guard isDir.boolValue else { return nil }
            let worktrees = fetchWorktrees(repoPath: path)
            guard !worktrees.isEmpty else { return nil }
            return GitRepo(name: name, mainPath: path, worktrees: worktrees)
        }
    }

    private nonisolated static func fetchWorktrees(repoPath: String) -> [GitWorktree] {
        let (output, code) = runGit("-C", repoPath, "worktree", "list", "--porcelain")
        if code != 0 {
            return [GitWorktree(path: repoPath, branch: nil, isMain: true)]
        }
        return parseWorktreeOutput(output)
    }

    private nonisolated static func parseWorktreeOutput(_ output: String) -> [GitWorktree] {
        let blocks = output.components(separatedBy: "\n\n")
        return blocks.enumerated().compactMap { index, block -> GitWorktree? in
            var path: String?
            var branch: String?
            var isDetached = false
            for line in block.components(separatedBy: "\n") {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch ") {
                    branch = String(line.dropFirst("branch ".count))
                        .components(separatedBy: "/").last
                } else if line == "detached" {
                    isDetached = true
                }
            }
            guard let wtPath = path, !wtPath.isEmpty else { return nil }
            return GitWorktree(path: wtPath, branch: isDetached ? nil : branch, isMain: index == 0)
        }
    }

    private nonisolated static func runGit(_ args: String...) -> (String, Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = Array(args)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return ("", -1) }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
    }
}

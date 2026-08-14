import Foundation

/// Discovers git repos under a root folder.
public enum RepoScanner {
    /// If `root` itself is a git repo (has a `.git` entry), returns it as a single `GitRepo` with
    /// worktrees from `worktreeLister`. Otherwise scans `root`'s immediate subdirectories for git
    /// repos. If none of those are git repos either, `root` itself is returned as a single
    /// non-git "repo" (`isGitRepo: false`) with one synthetic main worktree, so the sidebar can
    /// still show a plain folder uniformly alongside real repos. Paths in `excluding` are skipped
    /// entirely, including the root-itself and fallback cases.
    ///
    /// `worktreeLister` is injected (rather than shelling out to `git worktree list` directly) so
    /// this is testable against a plain directory tree without git installed or real repos.
    public static func findRepos(
        under root: String,
        excluding: Set<String>,
        worktreeLister: @Sendable (String) async -> [GitWorktree]
    ) async -> [GitRepo] {
        let files = FileManager.default

        var isGitDir: ObjCBool = false
        files.fileExists(atPath: root + "/.git", isDirectory: &isGitDir)
        if isGitDir.boolValue {
            guard !excluding.contains(root) else { return [] }
            let worktrees = await worktreeLister(root)
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
            let worktrees = await worktreeLister(path)
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
}

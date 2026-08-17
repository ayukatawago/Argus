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
    /// Returns `nil` when `root` exists but its contents couldn't be listed (permission blip,
    /// momentarily unavailable network/external volume) — a *definite* "no repos" (`root` doesn't
    /// exist, or is empty) is `[]`. Callers should treat `nil` as "unknown, keep whatever was
    /// known before" rather than as "there's nothing here now" — otherwise a transient listing
    /// failure wipes every worktree row under `root` until the next successful scan.
    ///
    /// `worktreeLister` is injected (rather than shelling out to `git worktree list` directly) so
    /// this is testable against a plain directory tree without git installed or real repos.
    public static func findRepos(
        under root: String,
        excluding: Set<String>,
        worktreeLister: @Sendable (String) async -> [GitWorktree]
    ) async -> [GitRepo]? {
        let files = FileManager.default
        guard files.fileExists(atPath: root) else { return [] }

        if isGitDirectory(root, files: files) {
            return await gitRepo(at: root, excluding: excluding, worktreeLister: worktreeLister)
        }

        guard let entries = try? files.contentsOfDirectory(atPath: root) else { return nil }
        var found: [GitRepo] = []
        for name in entries.sorted() {
            let path = root + "/" + name
            guard !excluding.contains(path), isGitDirectory(path, files: files) else { continue }
            found.append(contentsOf: await gitRepo(at: path, excluding: excluding, worktreeLister: worktreeLister))
        }
        return found.isEmpty ? plainFolderFallback(for: root, excluding: excluding) : found
    }

    private static func isGitDirectory(_ path: String, files: FileManager) -> Bool {
        var isDir: ObjCBool = false
        files.fileExists(atPath: path + "/.git", isDirectory: &isDir)
        return isDir.boolValue
    }

    /// A single-element array wrapping `path` itself as a `GitRepo`, or `[]` if it's excluded or
    /// its worktree list came back empty.
    private static func gitRepo(
        at path: String,
        excluding: Set<String>,
        worktreeLister: @Sendable (String) async -> [GitWorktree]
    ) async -> [GitRepo] {
        guard !excluding.contains(path) else { return [] }
        let worktrees = await worktreeLister(path)
        guard !worktrees.isEmpty else { return [] }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return [GitRepo(name: name, mainPath: path, worktrees: worktrees)]
    }

    private static func plainFolderFallback(for root: String, excluding: Set<String>) -> [GitRepo] {
        guard !excluding.contains(root) else { return [] }
        let name = URL(fileURLWithPath: root).lastPathComponent
        let worktree = GitWorktree(path: root, branch: nil, isMain: true)
        return [GitRepo(name: name, mainPath: root, worktrees: [worktree], isGitRepo: false)]
    }
}

import Foundation

/// Decides how `argus add <path>` changes the scan configuration so the repo at `path` shows up in
/// the sidebar exactly once.
///
/// `WorkspaceStore.refresh()` concatenates repos across roots with no dedupe, so a path that is both
/// its own root *and* a child of another scanned root would yield two `GitRepo`s with the same id.
/// The "already covered" check therefore has to be right, which is why it lives here, pure and
/// testable, rather than inside `WorkspaceStore`.
public enum RepoAddPlanner {
    public struct Plan: Equatable, Sendable {
        public var roots: [String]
        public var excluded: Set<String>
    }

    /// `resolve` normalizes a path (symlinks, trailing slashes) so a stored root spelled one way and
    /// a CLI-supplied path spelled another still compare equal. `isGitRepo` reports whether a path
    /// is itself a repo `RepoScanner` would treat as a root (its `.git` is a directory).
    public static func plan(
        path: String,
        roots: [String],
        excluded: Set<String>,
        isGitRepo: (String) -> Bool,
        resolve: (String) -> String
    ) -> Plan {
        let target = resolve(path)
        let newExcluded = excluded.filter { resolve($0) != target }

        let alreadyRoot = roots.contains { resolve($0) == target }
        let parent = (target as NSString).deletingLastPathComponent
        // `RepoScanner` scans a root's immediate children only when the root is not itself a repo.
        let coveredByParent = roots.contains { resolve($0) == parent && !isGitRepo(resolve($0)) }

        var newRoots = roots
        if !alreadyRoot, !coveredByParent { newRoots.append(path) }
        return Plan(roots: newRoots, excluded: newExcluded)
    }
}

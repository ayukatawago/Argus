import Foundation

/// Pure worktree-path -> repo lookup, for callers that need to resolve which project a worktree
/// belongs to (e.g. a per-project setting keyed by `GitRepo.mainPath`).
public enum RepoLookup {
    /// The `mainPath` of the repo owning the worktree at `path` (`GitWorktree.id` *is* its path),
    /// or `nil` when no tracked repo contains it.
    public static func mainPath(forWorktreePath path: String, in repos: [GitRepo]) -> String? {
        repos.first { repo in repo.worktrees.contains { $0.path == path } }?.mainPath
    }
}

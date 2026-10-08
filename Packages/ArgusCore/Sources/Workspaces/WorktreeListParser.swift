import Foundation

/// Parses `git worktree list --porcelain` output into `GitWorktree` values.
public enum WorktreeListParser {
    /// Blocks are separated by a blank line, one per worktree, in the order git prints them
    /// (main worktree first). Each block is a handful of `key value` lines; a bare `detached`
    /// line replaces the `branch` line for a detached HEAD.
    ///
    /// Locks current behavior: `branch` takes only the last path component of the ref
    /// (`.components(separatedBy: "/").last`), so `refs/heads/feature/foo` displays as `foo`, not
    /// `feature/foo`. This looks like a bug — a branch named `feature/foo` should probably show in
    /// full — but it's the existing, shipped behavior; changing it is a product decision, not part
    /// of this refactor.
    public static func parse(_ output: String) -> [GitWorktree] {
        let blocks = output.components(separatedBy: "\n\n")
        let parsed = blocks.compactMap { block -> GitWorktree? in
            var path: String?
            var branch: String?
            var isDetached = false
            for line in block.components(separatedBy: "\n") {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch ") {
                    branch =
                        String(line.dropFirst("branch ".count))
                        .components(separatedBy: "/").last
                } else if line == "detached" {
                    isDetached = true
                }
            }
            guard let wtPath = path, !wtPath.isEmpty else { return nil }
            return GitWorktree(path: wtPath, branch: isDetached ? nil : branch, isMain: false)
        }
        // Git lists the main worktree first, so it is the first block that *parsed* — keyed off the
        // raw block index, a malformed or empty leading block left the output with no main worktree.
        return parsed.enumerated().map { index, worktree in
            GitWorktree(path: worktree.path, branch: worktree.branch, isMain: index == 0)
        }
    }
}

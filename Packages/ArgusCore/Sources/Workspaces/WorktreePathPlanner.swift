import Foundation

/// Where a new git worktree for a branch is created: a sibling of the repo's main checkout, named
/// after the branch.
public enum WorktreePathPlanner {
    /// `<parent of repoMainPath>/<branch with "/" replaced by "-">`, or `nil` when the branch name
    /// can't yield a safe folder name — empty, only whitespace, or `.` / `..` (which would resolve
    /// to the parent directory itself or escape it).
    public static func path(forBranch branch: String, repoMainPath: String) -> String? {
        let folder = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !folder.isEmpty, folder != ".", folder != "..", !folder.contains("\0") else { return nil }
        let parent = URL(fileURLWithPath: repoMainPath).deletingLastPathComponent().path
        return (parent as NSString).appendingPathComponent(folder)
    }
}

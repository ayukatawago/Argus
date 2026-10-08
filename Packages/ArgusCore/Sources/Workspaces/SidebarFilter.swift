import ArgusSupport
import Foundation

/// Narrows the sidebar's repo list by a search query and/or an "needs attention" worktree set.
public enum SidebarFilter {
    /// `repos` reduced to worktrees matching `query` (against the repo name, branch and folder
    /// name) and, when `attentionIDs` is non-nil, belonging to that set. Repos left with no
    /// worktrees are dropped. A repo-name match keeps all of that repo's worktrees (still subject
    /// to `attentionIDs`). Empty query and nil `attentionIDs` returns `repos` untouched.
    public static func apply(repos: [GitRepo], query: String, attentionIDs: Set<String>?) -> [GitRepo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty && attentionIDs == nil { return repos }
        return repos.compactMap { repo in
            let repoMatches = trimmed.isEmpty || FuzzyMatcher.score(query: trimmed, in: repo.name) != nil
            let kept = repo.worktrees.filter { worktree in
                if let attentionIDs, !attentionIDs.contains(worktree.id) { return false }
                if repoMatches { return true }
                let names = [worktree.branch ?? "", URL(fileURLWithPath: worktree.path).lastPathComponent]
                return FuzzyMatcher.bestScore(query: trimmed, in: names) != nil
            }
            guard !kept.isEmpty else { return nil }
            var copy = repo
            copy.worktrees = kept
            return copy
        }
    }
}

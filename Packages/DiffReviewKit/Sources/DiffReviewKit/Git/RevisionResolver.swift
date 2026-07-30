import Foundation

/// Resolves git refs and a sensible default base branch for a diff review.
public struct RevisionResolver: Sendable {
    public let git: GitRunner

    public init(git: GitRunner) {
        self.git = git
    }

    /// Local and remote branch names, most-recently-committed first.
    public func listBranches() async -> [String] {
        let result = try? await git.run([
            "for-each-ref",
            "--sort=-committerdate",
            "--format=%(refname:short)",
            "refs/heads/", "refs/remotes/",
        ])
        guard let result, result.succeeded else { return [] }
        return result.standardOutput
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasSuffix("/HEAD") }
    }

    /// Best-effort default base ref: the remote's default branch (origin/HEAD), falling back to
    /// `origin/main`, `origin/master`, `main`, then `master`.
    public func defaultBase() async -> String {
        if let symbolic = try? await git.run(["symbolic-ref", "refs/remotes/origin/HEAD"]),
            symbolic.succeeded
        {
            let ref = symbolic.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let short = ref.replacingOccurrences(of: "refs/remotes/", with: "")
            if !short.isEmpty { return short }
        }
        for candidate in ["origin/main", "origin/master", "main", "master"] {
            if let check = try? await git.run(["rev-parse", "--verify", "--quiet", candidate]),
                check.succeeded
            {
                return candidate
            }
        }
        return "HEAD"
    }

    /// The worktree's current branch name (short form), or `nil` when detached.
    public func currentBranch() async -> String? {
        guard let result = try? await git.run(["symbolic-ref", "--short", "-q", "HEAD"]), result.succeeded
        else { return nil }
        let name = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
